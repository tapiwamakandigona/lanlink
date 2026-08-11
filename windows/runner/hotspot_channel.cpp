// Windows implementation of the "lanlink/hotspot" MethodChannel.
//
// Primary path: Wi-Fi Direct legacy soft-AP (WiFiDirectAdvertisementPublisher
// with LegacySettings) — works fully offline, lets us pick SSID/passphrase.
// Fallback / piggyback: Windows Mobile Hotspot via
// NetworkOperatorTetheringManager (used when Mobile Hotspot is already on —
// it takes precedence over all Wi-Fi Direct scenarios — or when the WFD
// publisher aborts, e.g. driver without Wi-Fi Direct support).
//
// Threading: channel callbacks arrive on the platform (UI) thread. C++/WinRT
// blocking .get() would deadlock/jank there, so method bodies run on detached
// MTA worker threads and results are marshalled back to the platform thread
// through the MainThreadDispatcher (a PostMessage trampoline wired up in
// flutter_window.cpp), because flutter::MethodResult is not thread-safe.

// Winsock 2 must come before <windows.h> (which flutter headers pull in),
// otherwise the legacy winsock.h gets included first and conflicts.
#include <winsock2.h>
#include <ws2tcpip.h>   // inet_ntop            (link ws2_32.lib)
#include <windows.h>
#include <iphlpapi.h>   // GetAdaptersAddresses (link iphlpapi.lib)
#include <wincrypt.h>   // DATA_BLOB
#include <dpapi.h>      // CryptProtectData/CryptUnprotectData (link crypt32.lib)

#include "hotspot_channel.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

// C++/WinRT projection headers ship inside the Windows SDK
// (Include\<ver>\cppwinrt\winrt\...); the Visual Studio generator's include
// path already contains them, so no NuGet/cppwinrt.exe step is needed for
// system WinRT APIs. The runner builds /std:c++17, which is all C++/WinRT
// requires. We deliberately use blocking .get() on worker threads instead of
// co_await, so the /await compiler flag is NOT needed.
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.WiFiDirect.h>
#include <winrt/Windows.Networking.Connectivity.h>
#include <winrt/Windows.Networking.NetworkOperators.h>
#include <winrt/Windows.Security.Credentials.h>

#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <fstream>
#include <functional>
#include <iostream>
#include <memory>
#include <mutex>
#include <optional>
#include <random>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

using namespace winrt::Windows::Devices::WiFiDirect;
using namespace winrt::Windows::Networking::Connectivity;
using namespace winrt::Windows::Networking::NetworkOperators;
using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

// ---------------------------------------------------------------------------
// State (all mutated under g_mutex; WinRT objects kept alive while running).
// ---------------------------------------------------------------------------
std::mutex g_mutex;
MainThreadDispatcher g_dispatch;

enum class Mode { kNone, kWifiDirect, kTethering };
Mode g_mode = Mode::kNone;

WiFiDirectAdvertisementPublisher g_publisher{nullptr};
WiFiDirectConnectionListener g_listener{nullptr};  // keep alive; auto-accept
winrt::event_token g_status_token{};
winrt::event_token g_conn_token{};
NetworkOperatorTetheringManager g_tethering{nullptr};
bool g_we_started_tethering = false;

// Bumped by every DoStop. An in-flight DoStart captures the value at entry
// and refuses to commit (tearing down whatever it just started) if a stop
// happened in between — otherwise stop() racing a slow start() could leave a
// live hotspot the app no longer knows about.
std::uint64_t g_generation = 0;

std::string g_ssid;
std::string g_password;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
void LogError(const std::string& message) {
  std::cerr << "[hotspot] " << message << std::endl;
}

std::string RandomSuffix(size_t length) {
  // No easily-confused characters (0/O, 1/l/I).
  static constexpr char kAlnum[] =
      "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  // Used for the WPA2 passphrase, so entropy matters: std::random_device is
  // CSPRNG-backed on MSVC, and drawing every character from it directly gives
  // the full character-space entropy. (Seeding an mt19937 from a single rd()
  // word would collapse the whole string to a 2^32 search space.)
  std::random_device rd;
  std::uniform_int_distribution<int> dist(
      0, static_cast<int>(sizeof(kAlnum)) - 2);
  std::string s;
  s.reserve(length);
  for (size_t i = 0; i < length; ++i) {
    s += kAlnum[dist(rd)];
  }
  return s;
}

// IPv4 addresses of this machine, hosted interface FIRST. The hosted
// interface is the "Microsoft Wi-Fi Direct Virtual Adapter" (WFD group owner)
// or the Mobile Hotspot's virtual adapter; both get 192.168.137.1 from the
// ICS service (icssvc) by default — but the range is registry-configurable,
// so we match on adapter description OR the 192.168.137.* default rather than
// hard-coding a single address.
std::vector<std::string> CollectHostIps() {
  constexpr ULONG kFlags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
                           GAA_FLAG_SKIP_DNS_SERVER;
  ULONG size = 0;
  GetAdaptersAddresses(AF_INET, kFlags, nullptr, nullptr, &size);
  if (size == 0) {
    return {};
  }
  std::vector<uint8_t> buffer(size);
  auto* addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  if (GetAdaptersAddresses(AF_INET, kFlags, nullptr, addresses, &size) !=
      NO_ERROR) {
    return {};
  }
  std::vector<std::string> hosted;
  std::vector<std::string> others;
  for (auto* adapter = addresses; adapter; adapter = adapter->Next) {
    if (adapter->OperStatus != IfOperStatusUp ||
        adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK) {
      continue;
    }
    std::wstring description =
        adapter->Description ? adapter->Description : L"";
    bool is_hosted =
        description.find(L"Wi-Fi Direct Virtual Adapter") != std::wstring::npos;
    for (auto* unicast = adapter->FirstUnicastAddress; unicast;
         unicast = unicast->Next) {
      if (unicast->Address.lpSockaddr->sa_family != AF_INET) {
        continue;
      }
      auto* sa = reinterpret_cast<sockaddr_in*>(unicast->Address.lpSockaddr);
      char ip[INET_ADDRSTRLEN] = {};
      if (!inet_ntop(AF_INET, &sa->sin_addr, ip, sizeof(ip))) {
        continue;
      }
      std::string s(ip);
      if (s.rfind("169.254.", 0) == 0) {
        continue;  // APIPA — never routable to a hotspot client.
      }
      if (is_hosted || s.rfind("192.168.137.", 0) == 0) {
        hosted.push_back(s);
      } else {
        others.push_back(s);
      }
    }
  }
  hosted.insert(hosted.end(), others.begin(), others.end());
  return hosted;
}

// The hosted adapter appears & gets its ICS address a beat after start
// succeeds — poll briefly (~5 s) for a 192.168.137.x address.
std::vector<std::string> WaitForHostIps() {
  for (int i = 0; i < 20; ++i) {
    auto ips = CollectHostIps();
    if (!ips.empty() && ips.front().rfind("192.168.137.", 0) == 0) {
      return ips;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(250));
  }
  return CollectHostIps();  // Best effort — contract allows any order.
}

// ---------------------------------------------------------------------------
// Persistent WFD credentials
// ---------------------------------------------------------------------------
// Android records a per-app "user approved this network" entry after the
// FIRST successful WifiNetworkSpecifier join; every later join to the SAME
// ssid+passphrase is silent (no system dialog). Regenerating credentials on
// every start destroyed that, so the WFD path persists them under
// %APPDATA%\LanLink\hotspot_creds and reloads them on each start,
// regenerating only when the file is missing or invalid. The file is a DPAPI
// (per-user) encrypted blob prefixed with the "LLC1" magic; older installs
// wrote two plaintext lines (ssid, passphrase), which are still readable and
// get transparently re-saved encrypted on first load (one-time migration).
// The Mobile-Hotspot piggyback paths are deliberately NOT persisted: they
// report Windows' own hotspot credentials, which we don't own.

// Plain printable ASCII only: the QR payload, the WinRT LegacySettings and
// Android's byte-exact SSID matching all agree on that subset.
bool IsPrintableAscii(const std::string& value) {
  for (char c : value) {
    if (c < 0x20 || c > 0x7e) {
      return false;
    }
  }
  return true;
}

bool IsValidSsid(const std::string& ssid) {
  if (ssid.empty() || ssid.size() > 32 || !IsPrintableAscii(ssid)) {
    return false;
  }
  // Leading/trailing spaces survive a QR round-trip badly (Android matches
  // SSIDs byte-exactly) — treat them as corrupt.
  return ssid.front() != ' ' && ssid.back() != ' ';
}

bool IsValidPassphrase(const std::string& pass) {
  // WPA2-PSK passphrase: 8..63 ASCII characters.
  return pass.size() >= 8 && pass.size() <= 63 && IsPrintableAscii(pass);
}

// %APPDATA%\LanLink\hotspot_creds. Empty optional when APPDATA is unset or
// the directory can't be created.
std::optional<std::wstring> CredsFilePath(bool create_dir) {
  wchar_t appdata[MAX_PATH] = {};
  DWORD len = GetEnvironmentVariableW(L"APPDATA", appdata, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) {
    return std::nullopt;
  }
  std::wstring dir(appdata);
  dir += L"\\LanLink";
  if (create_dir && !CreateDirectoryW(dir.c_str(), nullptr) &&
      GetLastError() != ERROR_ALREADY_EXISTS) {
    return std::nullopt;
  }
  return dir + L"\\hotspot_creds";
}

// Magic header marking the DPAPI-encrypted credential format. Anything else
// is treated as the legacy two-line plaintext format (DPAPI ciphertext always
// starts with a fixed GUID, so a plaintext SSID can never collide with this).
constexpr char kCredsMagic[] = "LLC1";
constexpr size_t kCredsMagicLen = 4;

// Per-user DPAPI encrypt. The description string shows up in DPAPI audit
// tooling; it is not a secret. UI_FORBIDDEN because we run non-interactive.
bool DpapiEncrypt(const std::string& plaintext, std::vector<uint8_t>* out) {
  DATA_BLOB in{};
  in.pbData =
      reinterpret_cast<BYTE*>(const_cast<char*>(plaintext.data()));
  in.cbData = static_cast<DWORD>(plaintext.size());
  DATA_BLOB encrypted{};
  if (!CryptProtectData(&in, L"LanLink hotspot credentials", nullptr, nullptr,
                        nullptr, CRYPTPROTECT_UI_FORBIDDEN, &encrypted)) {
    return false;
  }
  out->assign(encrypted.pbData, encrypted.pbData + encrypted.cbData);
  LocalFree(encrypted.pbData);
  return true;
}

bool DpapiDecrypt(const uint8_t* data, size_t size, std::string* out) {
  DATA_BLOB in{};
  in.pbData = const_cast<BYTE*>(data);
  in.cbData = static_cast<DWORD>(size);
  DATA_BLOB decrypted{};
  if (!CryptUnprotectData(&in, nullptr, nullptr, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &decrypted)) {
    return false;
  }
  out->assign(reinterpret_cast<char*>(decrypted.pbData), decrypted.cbData);
  LocalFree(decrypted.pbData);
  return true;
}

// Parses "ssid\npass" (optionally CRLF / trailing newline) and validates.
// Shared by both the decrypted-blob and legacy-plaintext load paths.
bool ParseAndValidateCreds(const std::string& text, std::string* ssid,
                           std::string* pass) {
  std::istringstream stream(text);
  std::string s;
  std::string p;
  if (!std::getline(stream, s) || !std::getline(stream, p)) {
    return false;
  }
  // Tolerate CRLF from hand-edited files.
  if (!s.empty() && s.back() == '\r') s.pop_back();
  if (!p.empty() && p.back() == '\r') p.pop_back();
  if (!IsValidSsid(s) || !IsValidPassphrase(p)) {
    return false;
  }
  *ssid = s;
  *pass = p;
  return true;
}

void SavePersistedCreds(const std::string& ssid, const std::string& pass) {
  auto path = CredsFilePath(/*create_dir=*/true);
  if (!path) {
    LogError("could not resolve creds path; hotspot creds not persisted");
    return;
  }
  std::vector<uint8_t> blob;
  if (!DpapiEncrypt(ssid + "\n" + pass + "\n", &blob)) {
    // Fail closed: better to regenerate next run than persist plaintext.
    LogError("DPAPI encrypt failed; hotspot creds not persisted");
    return;
  }
  std::ofstream file(path->c_str(),
                     std::ios::binary | std::ios::trunc);  // wide-path: MSVC
  if (!file) {
    LogError("could not write hotspot creds file");
    return;
  }
  file.write(kCredsMagic, kCredsMagicLen);
  file.write(reinterpret_cast<const char*>(blob.data()),
             static_cast<std::streamsize>(blob.size()));
}

// Returns true and fills ssid/pass only when the persisted values pass
// validation; any malformed or undecryptable file is ignored (caller
// regenerates). Legacy plaintext files are re-saved encrypted on the spot.
bool LoadPersistedCreds(std::string* ssid, std::string* pass) {
  auto path = CredsFilePath(/*create_dir=*/false);
  if (!path) {
    return false;
  }
  std::string raw;
  {
    std::ifstream file(path->c_str(),
                       std::ios::binary);  // MSVC supports wide-path streams.
    if (!file) {
      return false;
    }
    std::ostringstream buffer;
    buffer << file.rdbuf();
    raw = buffer.str();
  }
  if (raw.size() >= kCredsMagicLen &&
      raw.compare(0, kCredsMagicLen, kCredsMagic, kCredsMagicLen) == 0) {
    std::string plaintext;
    if (!DpapiDecrypt(
            reinterpret_cast<const uint8_t*>(raw.data()) + kCredsMagicLen,
            raw.size() - kCredsMagicLen, &plaintext)) {
      return false;  // Corrupt blob or copied from another user/machine.
    }
    return ParseAndValidateCreds(plaintext, ssid, pass);
  }
  // Legacy plaintext format — migrate to the encrypted format once.
  if (!ParseAndValidateCreds(raw, ssid, pass)) {
    return false;
  }
  SavePersistedCreds(*ssid, *pass);
  return true;
}

// ---------------------------------------------------------------------------
// Fallback: Mobile Hotspot via NetworkOperatorTetheringManager
// ---------------------------------------------------------------------------
// CreateFromConnectionProfile needs a non-null profile, but
// GetInternetConnectionProfile() returns null when the PC has no internet.
// Undocumented-but-proven workaround: any profile from GetConnectionProfiles()
// (even a disconnected Ethernet) satisfies the API. With no profiles at all
// (rare: airplane mode + no NICs) this path is unavailable.
NetworkOperatorTetheringManager GetTetheringManager() {
  ConnectionProfile profile = NetworkInformation::GetInternetConnectionProfile();
  if (!profile) {
    auto all = NetworkInformation::GetConnectionProfiles();
    if (all.Size() > 0) {
      profile = all.GetAt(0);
    }
  }
  if (!profile) {
    return nullptr;
  }
  if (NetworkOperatorTetheringManager::GetTetheringCapabilityFromConnectionProfile(
          profile) != TetheringCapability::Enabled) {
    return nullptr;
  }
  return NetworkOperatorTetheringManager::CreateFromConnectionProfile(profile);
}

// Returns true + records ssid/pass on success. Blocking; worker thread only.
bool StartTetheringFallback(std::string* err, std::uint64_t start_generation) {
  auto manager = GetTetheringManager();
  if (!manager) {
    *err = "tethering unavailable (no connection profile, or disabled by "
           "policy/hardware)";
    return false;
  }
  // Read the user's existing persistent hotspot credentials — we do NOT
  // rewrite them (ConfigureAccessPointAsync would persist our values into
  // Windows Settings, which is surprising to users). The QR carries whatever
  // SSID/passphrase Windows already has.
  auto config = manager.GetCurrentAccessPointConfiguration();
  bool we_started = false;
  if (manager.TetheringOperationalState() != TetheringOperationalState::On) {
    auto result = manager.StartTetheringAsync().get();  // blocking WinRT wait
    auto status = result.Status();
    if (status != TetheringOperationStatus::Success) {
      *err = "StartTetheringAsync failed, status=" +
             std::to_string(static_cast<int>(status)) + " " +
             winrt::to_string(result.AdditionalErrorMessage());
      return false;
    }
    we_started = true;  // stop() only stops what we started
  }
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_generation == start_generation) {
      g_tethering = manager;
      g_we_started_tethering = we_started;
      g_ssid = winrt::to_string(config.Ssid());
      g_password = winrt::to_string(config.Passphrase());
      g_mode = Mode::kTethering;
      return true;
    }
  }
  // stop() ran while we were starting. Only undo tethering we started
  // ourselves; the blocking stop happens outside g_mutex.
  if (we_started) {
    try {
      manager.StopTetheringAsync().get();
    } catch (...) {
    }
  }
  *err = "cancelled by stop()";
  return false;
}

// ---------------------------------------------------------------------------
// Primary: Wi-Fi Direct legacy soft-AP
// ---------------------------------------------------------------------------
// Blocking; worker thread only. Waits for the publisher's StatusChanged to
// report Started (or Aborted) before returning.
//
// The wait state is heap-shared with the event handler: on timeout this
// function returns while the publisher callback may still fire later, so the
// handler must never reference this frame's stack.
struct PublisherWaitState {
  std::mutex mutex;
  std::condition_variable cv;
  std::optional<WiFiDirectAdvertisementPublisherStatus> final_status;
  WiFiDirectError error = WiFiDirectError::Success;
};

bool StartWifiDirect(std::string* err, std::uint64_t start_generation) {
  // Stable credentials across runs (see "Persistent WFD credentials" above):
  // reuse the persisted pair when valid, otherwise mint + persist a new one.
  std::string ssid;
  std::string pass;
  if (!LoadPersistedCreds(&ssid, &pass)) {
    ssid = "LanLink-" + RandomSuffix(4);
    // Passphrase MUST be >= 8 chars, otherwise Start() aborts with an unknown
    // error. Do NOT use a "DIRECT-" SSID prefix: Android applies special P2P
    // heuristics to those; a plain name keeps WifiNetworkSpecifier on the
    // ordinary STA join path.
    pass = RandomSuffix(10);
    SavePersistedCreds(ssid, pass);
  }

  WiFiDirectAdvertisementPublisher publisher;
  auto advertisement = publisher.Advertisement();
  // Legacy WFD advertisement uses an autonomous group owner as the AP.
  advertisement.IsAutonomousGroupOwnerEnabled(true);
  auto legacy = advertisement.LegacySettings();
  legacy.IsEnabled(true);  // plain-WPA2 access point behavior
  legacy.Ssid(winrt::to_hstring(ssid));
  winrt::Windows::Security::Credentials::PasswordCredential credential;
  credential.Password(winrt::to_hstring(pass));
  legacy.Passphrase(credential);
  advertisement.ListenStateDiscoverability(
      WiFiDirectAdvertisementListenStateDiscoverability::Normal);

  // Bridge the StatusChanged event into a synchronous wait.
  auto wait = std::make_shared<PublisherWaitState>();
  auto status_token = publisher.StatusChanged(
      [wait](WiFiDirectAdvertisementPublisher const&,
             WiFiDirectAdvertisementPublisherStatusChangedEventArgs const& e) {
        auto status = e.Status();
        if (status == WiFiDirectAdvertisementPublisherStatus::Started ||
            status == WiFiDirectAdvertisementPublisherStatus::Aborted) {
          std::lock_guard<std::mutex> lock(wait->mutex);
          wait->final_status = status;
          wait->error = e.Error();
          wait->cv.notify_all();
        }
      });

  // Auto-accept incoming connections (mirrors the WiFiDirectLegacyAP sample;
  // WPA2-PSK auth itself is handled by the driver, but keeping a listener
  // that resolves WiFiDirectDevice::FromIdAsync prevents pairing-prompt
  // stalls on some drivers). Note: per-client ConnectionStatusChanged /
  // disconnect callbacks are unreliable (Windows-classic-samples issue #82) —
  // LanLink relies on its own TCP liveness instead.
  WiFiDirectConnectionListener listener;
  auto conn_token = listener.ConnectionRequested(
      [](WiFiDirectConnectionListener const&,
         WiFiDirectConnectionRequestedEventArgs const& e) {
        try {
          auto request = e.GetConnectionRequest();
          // Fire-and-forget accept.
          WiFiDirectDevice::FromIdAsync(request.DeviceInformation().Id());
        } catch (...) {
        }
      });

  publisher.Start();
  WiFiDirectAdvertisementPublisherStatus final_status =
      WiFiDirectAdvertisementPublisherStatus::Created;
  WiFiDirectError final_error = WiFiDirectError::Success;
  {
    std::unique_lock<std::mutex> lock(wait->mutex);
    if (!wait->cv.wait_for(lock, std::chrono::seconds(10),
                           [&] { return wait->final_status.has_value(); })) {
      lock.unlock();
      publisher.StatusChanged(status_token);
      listener.ConnectionRequested(conn_token);
      try {
        publisher.Stop();
      } catch (...) {
      }
      *err = "WFD publisher start timed out";
      return false;
    }
    // Copy while still holding wait->mutex: the StatusChanged handler is
    // still subscribed and may fire again (e.g. Started -> Aborted),
    // rewriting these fields concurrently with any unlocked read.
    final_status = *wait->final_status;
    final_error = wait->error;
  }
  if (final_status != WiFiDirectAdvertisementPublisherStatus::Started) {
    publisher.StatusChanged(status_token);
    listener.ConnectionRequested(conn_token);
    // WiFiDirectError: RadioNotAvailable (Wi-Fi off / airplane mode) or
    //                  ResourceInUse (Mobile Hotspot on, other GO active).
    *err = "WFD advertisement aborted, error=" +
           std::to_string(static_cast<int>(final_error));
    return false;
  }
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_generation == start_generation) {
      g_publisher = publisher;
      g_listener = listener;
      g_status_token = status_token;
      g_conn_token = conn_token;
      g_ssid = ssid;
      g_password = pass;
      g_mode = Mode::kWifiDirect;
      return true;
    }
  }
  // stop() ran while we were starting: tear down what we just started
  // (outside g_mutex) instead of stranding a live publisher.
  publisher.StatusChanged(status_token);
  listener.ConnectionRequested(conn_token);
  try {
    publisher.Stop();
  } catch (...) {
  }
  *err = "cancelled by stop()";
  return false;
}

// ---------------------------------------------------------------------------
// start / stop / isRunning / isSupported (blocking bodies, worker thread)
// ---------------------------------------------------------------------------
// Returns an EncodableValue map on success or monostate (-> Dart null) on
// failure.
EncodableValue DoStart() {
  bool started = false;
  std::uint64_t start_generation = 0;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    start_generation = g_generation;
  }

  // If Mobile Hotspot is ALREADY on, WFD cannot start (Mobile Hotspot takes
  // precedence over all Wi-Fi Direct scenarios) — just piggyback on it.
  try {
    auto manager = GetTetheringManager();
    if (manager &&
        manager.TetheringOperationalState() == TetheringOperationalState::On) {
      auto config = manager.GetCurrentAccessPointConfiguration();
      std::lock_guard<std::mutex> lock(g_mutex);
      if (g_generation != start_generation) {
        return EncodableValue();  // stop() raced us; nothing to undo
      }
      g_tethering = manager;
      g_we_started_tethering = false;
      g_ssid = winrt::to_string(config.Ssid());
      g_password = winrt::to_string(config.Passphrase());
      g_mode = Mode::kTethering;
      started = true;
    }
  } catch (winrt::hresult_error const&) {
    // Fall through to the normal start paths.
  }

  if (!started) {
    std::string wfd_error;
    std::string tethering_error;
    if (StartWifiDirect(&wfd_error, start_generation)) {
      started = true;
    } else {
      {
        std::lock_guard<std::mutex> lock(g_mutex);
        if (g_generation != start_generation) {
          return EncodableValue();  // stop() cancelled this start
        }
      }
      try {
        started = StartTetheringFallback(&tethering_error, start_generation);
      } catch (winrt::hresult_error const& e) {
        tethering_error = "hresult " + winrt::to_string(e.message());
      }
      if (!started) {
        LogError("start failed: WFD: " + wfd_error +
                 " / tethering: " + tethering_error);
        return EncodableValue();  // null to Dart
      }
    }
  }

  auto ips = WaitForHostIps();
  EncodableList ip_list;
  for (auto& ip : ips) {
    ip_list.emplace_back(ip);
  }
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_generation != start_generation) {
    return EncodableValue();  // stop() ran while polling IPs; state is gone
  }
  return EncodableValue(EncodableMap{
      {EncodableValue("ssid"), EncodableValue(g_ssid)},
      {EncodableValue("password"), EncodableValue(g_password)},
      {EncodableValue("hostIps"), EncodableValue(ip_list)},
  });
}

void DoStop() {
  // Snapshot-and-clear under g_mutex, then do the blocking WinRT stop calls
  // OUTSIDE the lock: StopTetheringAsync().get() can take seconds, and
  // Shutdown() (platform thread, app close) joins a worker running DoStop.
  Mode mode = Mode::kNone;
  WiFiDirectAdvertisementPublisher publisher{nullptr};
  WiFiDirectConnectionListener listener{nullptr};
  winrt::event_token status_token{};
  winrt::event_token conn_token{};
  NetworkOperatorTetheringManager tethering{nullptr};
  bool we_started_tethering = false;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    ++g_generation;  // cancels any in-flight DoStart (see g_generation)
    mode = g_mode;
    publisher = std::move(g_publisher);
    listener = std::move(g_listener);
    status_token = g_status_token;
    conn_token = g_conn_token;
    tethering = std::move(g_tethering);
    we_started_tethering = g_we_started_tethering;
    g_publisher = nullptr;
    g_listener = nullptr;
    g_status_token = {};
    g_conn_token = {};
    g_tethering = nullptr;
    g_mode = Mode::kNone;
    g_ssid.clear();
    g_password.clear();
    g_we_started_tethering = false;
  }
  if (mode == Mode::kWifiDirect && publisher) {
    try {
      // Revoke handlers before Stop(), as before.
      publisher.StatusChanged(status_token);
      listener.ConnectionRequested(conn_token);
      publisher.Stop();
    } catch (...) {
    }
  } else if (mode == Mode::kTethering && tethering && we_started_tethering) {
    // Only stop tethering we started; never turn off the user's own hotspot.
    try {
      tethering.StopTetheringAsync().get();
    } catch (...) {
    }
  }
}

bool DoIsRunning() {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_mode == Mode::kWifiDirect) {
    return g_publisher && g_publisher.Status() ==
                              WiFiDirectAdvertisementPublisherStatus::Started;
  }
  if (g_mode == Mode::kTethering) {
    return g_tethering && g_tethering.TetheringOperationalState() ==
                              TetheringOperationalState::On;
  }
  return false;
}

bool DoIsSupported() {
  // Cheap probe: any WLAN adapter present? (IF_TYPE_IEEE80211 includes
  // adapters whose radio is currently off — start() surfaces that later.)
  ULONG size = 0;
  GetAdaptersAddresses(AF_UNSPEC, 0, nullptr, nullptr, &size);
  if (size == 0) {
    return false;
  }
  std::vector<uint8_t> buffer(size);
  auto* addresses = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  if (GetAdaptersAddresses(AF_UNSPEC, 0, nullptr, addresses, &size) !=
      NO_ERROR) {
    return false;
  }
  for (auto* adapter = addresses; adapter; adapter = adapter->Next) {
    if (adapter->IfType == IF_TYPE_IEEE80211) {
      return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Threading harness
// ---------------------------------------------------------------------------
// Runs |body| on a detached MTA worker thread and marshals the result back to
// the platform thread through g_dispatch before completing |result|.
template <typename Fn>
void RunAsync(std::unique_ptr<flutter::MethodResult<EncodableValue>> result,
              Fn body) {
  auto shared_result =
      std::shared_ptr<flutter::MethodResult<EncodableValue>>(std::move(result));
  std::thread([shared_result, body]() {
    // Each worker gets its own MTA apartment. We intentionally never
    // uninitialize: WinRT objects created here are stored in globals and must
    // outlive the thread; the MTA stays alive for the process lifetime.
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    EncodableValue value;
    try {
      value = body();
    } catch (winrt::hresult_error const& e) {
      LogError("hresult error: " + winrt::to_string(e.message()));
      value = EncodableValue();  // -> Dart null
    } catch (...) {
      LogError("unknown native error");
      value = EncodableValue();
    }
    g_dispatch([shared_result, value]() { shared_result->Success(value); });
  }).detach();
}

}  // namespace

namespace hotspot_channel {

void Register(flutter::FlutterEngine* engine, MainThreadDispatcher dispatcher) {
  g_dispatch = std::move(dispatcher);
  static auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), "lanlink/hotspot",
          &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const auto& method = call.method_name();
        if (method == "hasPermission" || method == "requestPermission") {
          // Windows has no runtime-permission concept — trivially true
          // (pinned contract), answered synchronously on the platform thread.
          result->Success(EncodableValue(true));
        } else if (method == "isSupported") {
          RunAsync(std::move(result),
                   [] { return EncodableValue(DoIsSupported()); });
        } else if (method == "isRunning") {
          RunAsync(std::move(result),
                   [] { return EncodableValue(DoIsRunning()); });
        } else if (method == "start") {
          RunAsync(std::move(result), [] { return DoStart(); });
        } else if (method == "stop") {
          RunAsync(std::move(result), [] {
            DoStop();
            return EncodableValue();
          });
        } else {
          result->NotImplemented();
        }
      });
}

void Shutdown() {
  // Called from the platform (STA) thread on window destroy. DoStop() may
  // block on WinRT async (.get()), which asserts on an STA — run it on a
  // short-lived MTA worker and join.
  std::thread worker([] {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    try {
      DoStop();
    } catch (...) {
    }
  });
  worker.join();
}

}  // namespace hotspot_channel
