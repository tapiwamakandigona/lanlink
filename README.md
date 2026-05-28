# LanLink

> Fast, reliable local file sharing between Windows and Android. Same Wi-Fi, same hotspot, no internet, no account, no cloud.

LanLink is a single Flutter codebase that runs on **Android 8+** and **Windows 10/11**. Every running instance hosts its own HTTP server and announces itself on the local network, so transfers are peer-to-peer — PC ↔ phone, phone ↔ phone, and phone ↔ PC all work the same way.

LanLink speaks the [LocalSend v2 wire protocol](https://github.com/localsend/protocol), so it can also interoperate with LocalSend out of the box.

---

## Features

- **Peer-to-peer LAN transfers.** No central server, no cloud relay, no internet required.
- **Symmetric topology.** Phones can send to PCs, PCs to phones, and phones to phones — every device is both a sender and a receiver.
- **Three connectivity modes:**
  - **LAN** — standard Wi-Fi / wired LAN with UDP-multicast discovery.
  - **Hotspot** — phone-to-phone over a mobile hotspot, with a host/joining picker and an automatic subnet scan (no router required).
  - **Bluetooth** — falls back to the Android system share sheet (`ACTION_SEND_MULTIPLE`).
- **Hotspot UX:** pick "I'm hosting", "I'm joining", or "Detect for me". A subnet scan sweeps the local `/24` plus the well-known Android hotspot ranges (`192.168.43.0/24`, `192.168.49.0/24`) for any device answering `/api/localsend/v2/info`. Useful because phone hotspots typically drop UDP multicast.
- **QR pairing.** Show a QR code carrying this device's IP, port, alias, and fingerprint; the other phone scans it (camera preview, torch + camera-flip controls) and lands directly in the peer list. No typing required.
- **Per-peer nicknames + persistent trust.** Long-press a peer to assign a friendly name ("My laptop", "Tapiwa's phone") that survives restarts, jump to that peer's transfer history, or toggle their trusted status from one sheet.
- **Send to multiple peers at once.** Multi-select mode in the peer list — pick N nearby devices and fan out the same staged files to all of them as parallel sessions.
- **Per-peer transfer history.** Long-press a peer → "View history with this device" → only the transfers you've done with that fingerprint, regardless of what their alias was at the time.
- **Polished dark mode.** Hand-tuned dark palette (deep neutral surfaces, soft blue primary, designed contrast) instead of inverted Material defaults. Settings → Appearance lets you pick Follow system / Light / Dark.
- **Animated transfer outcome.** When a session reaches Done / Failed / Cancelled, its status chip scales in with a bouncy entrance and the matching check / X icon, so success is visible at a glance.
- **System notifications with progress on Android.** Incoming and outgoing transfers post an ongoing progress notification ("Receiving from Tapiwa's phone — 14.2 MB / 38.5 MB (37%)") that updates in the shade. On completion the notification swaps to "Received 3 files — Saved to Downloads/LanLink". Throttled to a 250ms update interval so we don't flood the NotificationManager.
- **Manual rescan button** in the app bar — pokes multicast and kicks the subnet scan in all modes.
- **Stream-based file I/O.** Files go straight from disk → network → disk; memory usage stays flat regardless of file size. Multi-gigabyte transfers work fine.
- **Live progress on both sides.** The sender and receiver both see real-time bytes-transferred — no more "stuck at 100%" with nothing actually delivered.
- **Android Downloads visibility.** Received files are published into `Downloads/LanLink` via `MediaStore`, so they show up in the Files app immediately on Android 10+ (which blocks direct `dart:io` writes to public Downloads under scoped storage). Android 9 and below get the legacy direct path. A per-file "Saved to ..." line in the receiver UI tells you exactly where each file landed.
- **Per-transfer accept prompt** so random devices on your network can't dump files on you. Optionally mark senders as **trusted** for one-tap acceptance next time.
- **Decline ≠ failure.** A peer that declines your send is reported as cancelled, not failed.
- **Cross-platform UX** that follows platform conventions (Material 3 light/dark, system theme).
- **Optional in-app update checker.** Polls the GitHub Releases API in the background and surfaces a dismissible "Update available" banner. Tap the banner (or **Settings → Updates → Check now**) to see the release notes and download the binary for your platform directly — never a link to the source code, and never a forced install.
- **Reproducible CI builds:** every PR produces a downloadable debug APK + Windows zip, and tags produce a signed release APK + NSIS installer.

---

## Quick start

### Run from source (development)

Requirements:

- Flutter SDK 3.24.5 (channel `stable`)
- JDK 17 (for Android builds)
- Android SDK + an emulator or USB-connected Android 8+ device (for the Android target)
- Windows host with Visual Studio C++ build tools (for the Windows target)

```bash
git clone https://github.com/tapiwamakandigona/lanlink.git
cd lanlink
flutter pub get

# Run on an attached Android device / emulator
flutter run -d android

# Run on Windows
flutter run -d windows
```

### Grab a build from CI

Every push to `main` and every pull request triggers a CI build. To pick up a fresh APK or Windows zip without setting up Flutter locally:

1. Go to [Actions](https://github.com/tapiwamakandigona/lanlink/actions) → pick the latest **CI** run.
2. Scroll to **Artifacts** and download `lanlink-android-debug` (an installable APK) or `lanlink-windows` (a zip with `lanlink.exe`).

### Install a tagged release

When a `v*` tag is pushed, the **Release** workflow produces a signed APK and a Windows NSIS installer and attaches them to the GitHub Release. See [Releases](https://github.com/tapiwamakandigona/lanlink/releases).

---

## How it works

### Discovery

Every LanLink instance opens a UDP socket on `224.0.0.167:53317` and announces itself every 5 seconds with a small JSON payload describing its alias, fingerprint, port, and device type. When another peer's announcement arrives, the receiver remembers them and (if it hasn't already) replies with its own announcement so the new peer learns about everyone already present.

For networks where multicast is blocked, the Home screen has an **Add device by IP** action that probes a manually entered `host:port` over HTTP.

In **Hotspot mode** the app also runs an active `SubnetScanner` in parallel with multicast — sweeping the local `/24` and the well-known Android hotspot subnets (`192.168.43.x`, `192.168.49.x`) with 32 concurrent HTTP probes against `/api/localsend/v2/info`. Anything that responds gets added to the peer list automatically.

### Transfer

LanLink follows the [LocalSend v2 HTTP protocol](https://github.com/localsend/protocol):

| Endpoint | Direction | Purpose |
|---|---|---|
| `GET /api/localsend/v2/info` | Either | Returns the device's `alias`, `version`, `deviceModel`, `deviceType`, `fingerprint`, `port`, and `protocol`. |
| `POST /api/localsend/v2/register` | Either | Lets a peer announce itself unicast and receive `info` back. |
| `POST /api/localsend/v2/prepare-upload` | Sender → receiver | Body contains `info` + a `files` manifest. Receiver shows a prompt; on accept, replies with a `sessionId` and a per-file `token`. |
| `POST /api/localsend/v2/upload?sessionId&fileId&token` | Sender → receiver | Body is the raw file bytes (no base64). Receiver streams them straight to disk via a `.part` temp file, then atomic-renames into the save folder. |
| `POST /api/localsend/v2/cancel?sessionId` | Either | Aborts an in-progress session. |

### Android scoped storage

On Android 10+ scoped storage blocks `dart:io` from writing into `/storage/emulated/0/Download/...` directly. LanLink handles this by:

1. Streaming the upload into the app's private external directory (`/Android/data/com.lanlink.app/files/LanLink/...`).
2. Once the file is fully written, calling a small Kotlin bridge (`MainActivity.publishToDownloads`) that copies it into `MediaStore.Downloads` with `RELATIVE_PATH = Download/LanLink/`.
3. Deleting the private copy on success.

That way the file is visible in the Files app the moment the transfer finishes, with no extra permission prompts on modern Android. Android 9 and below take the legacy direct path. The Settings page on Android shows a clear "Files are saved to Downloads/LanLink" hint instead of a folder picker, because Android's Storage Access Framework returns `content://` tree URIs that `dart:io` can't open. The picker is still available on Windows where the path-based API actually works.

### QR pairing

When multicast is blocked and you don't want to type IPs, both ends open the **QR** actions in the home page's "Nearby devices" header. The "Show QR" sheet renders a QR encoding a `lanlink://pair?ip=…&port=…&alias=…&fp=…` URI; the "Scan QR" page opens a camera viewfinder, decodes that URI, and calls the same `/info` probe path that manual IP entry uses. The QR payload is intentionally tiny so even low-end scanners can decode it from a phone screen.

### Per-peer state

User-assigned data (nicknames, trusted fingerprints) is keyed off the peer's **fingerprint** — a stable SHA-256 of the device's install identity — rather than its alias, which can change. That means a peer renamed in Settings will still be greeted as your nickname, and a peer marked trusted last week stays trusted even if they updated their device's name. Long-press any peer card to bring up the action sheet (rename / view history with this device / toggle trusted).

### Hotspot role detection

`HotspotRole.auto` inspects the device's IP addresses on every refresh. The interface IPs `192.168.43.1`, `192.168.49.1`, `192.168.1.1`, `10.0.0.1`, and `172.20.10.1` are treated as "I'm the AP". Anything else means we're a client. You can override the guess with the `I'm hosting` / `I'm joining` chips on the home screen.

### In-app updates

`UpdateChecker` (in `lib/core/update/`) polls the GitHub Releases API for `tapiwamakandigona/lanlink` on startup and on demand, then compares the latest tag against the running app's `PackageInfo.version` using `pub_semver`. If a strictly newer release exists, the home screen shows a dismissible banner. The detail sheet links directly to the Android `.apk` or Windows `.zip` asset for the running platform — **never** the GitHub release page (which would expose the source-code download), and **never** an auto-install. The user can:

- Tap **Download** → opens the binary URL in the system browser.
- Tap **Later** → banner stays.
- Tap **Skip this version** (or the × on the banner) → banner won't reappear until a newer release is published.
- Open **Settings → Updates** (or **About → Check for updates**) → manual recheck, clear a previously skipped version.

The manifest URL is a single constant in `lib/core/update/update_checker.dart` so it can be swapped for a hand-rolled JSON file hosted anywhere (e.g. a private repo's GitHub Pages, Firebase Hosting, your own site) when you take the source private. The download URLs in that manifest can also point anywhere — they don't have to be GitHub assets.

### Security model

- v2.0 ships **HTTP only** (no TLS). All traffic stays on the LAN / hotspot.
- Every incoming transfer triggers an in-app **Save / Decline** prompt unless the sender's fingerprint is in your **Trusted devices** list and **Quick Save** is enabled.
- Per-file `token`s are random UUIDs scoped to one session; uploads that miss the token are rejected.
- A TLS layer with per-install self-signed certificates and fingerprint-pinning is a planned follow-up (see [`docs/architecture.md`](docs/architecture.md) → "Risks and follow-ups").

### Repo layout

```
lanlink/
├── lib/
│   ├── core/
│   │   ├── connectivity/     # Connectivity mode + HotspotRole enum
│   │   ├── discovery/        # UDP multicast announce + listen + SubnetScanner
│   │   ├── models/           # Device, FileInfo, TransferSession
│   │   ├── protocol/         # Wire constants + route names
│   │   ├── server/           # (reserved for future TLS layer)
│   │   ├── settings/         # AppSettings (SharedPreferences-backed)
│   │   ├── transfer/         # Sender (dio) + Receiver (shelf)
│   │   ├── update/           # GitHub-releases update checker
│   │   └── util/             # network, fingerprint, formatting
│   ├── state/
│   │   └── app_state.dart    # Top-level ChangeNotifier
│   └── ui/
│       ├── home_page.dart
│       ├── settings_page.dart
│       ├── about_page.dart
│       ├── history_page.dart
│       └── widgets/          # DeviceCard, ProgressCard, ReceivePromptDialog,
│                             # UpdateAvailableBanner, CheckForUpdatesTile, ...
├── android/                  # Flutter Android runner (minSdk 26)
│   └── app/src/main/kotlin/com/lanlink/app/MainActivity.kt
│       # Hosts publishToDownloads() — copies finished files into
│       # MediaStore.Downloads so they show up in the Files app.
├── windows/                  # Flutter Windows runner
├── docs/architecture.md      # Architecture decision record
├── test/
│   ├── widget_test.dart
│   ├── transfer_loopback_test.dart   # End-to-end Sender↔Receiver over localhost
│   ├── subnet_scanner_test.dart      # SubnetScanner finds a fake /info server
│   └── update_checker_test.dart      # UpdateChecker version comparison
└── .github/workflows/
    ├── ci.yml                # PR + main: analyze, test, build APK + Windows zip
    └── release.yml           # Tag v*: signed APK + NSIS installer + GitHub Release
```

---

## Known limitations

- **Bluetooth mode is best-effort.** LanLink hands the selected files to the Android system share sheet and the OS performs the Bluetooth transfer. There's no Intent callback for "the user actually picked a target", so the session is optimistically marked completed once the chooser returns. True OBEX-based Bluetooth (à la ShareIt) is a separate follow-up.
- **No resume on dropped Wi-Fi.** A connection lost mid-upload fails the whole file; the protocol currently has no range header / resume token.
- **No TLS yet.** All transfers are HTTP. Treat untrusted networks accordingly.
- **Untrusted-source install on Android.** Sideloaded APKs need "Install unknown apps" enabled for the source (browser, file manager). The Play Store flow is on the roadmap once a release keystore is generated and enrolled in Play App Signing.
- **The update checker is read-only.** It opens the download URL in the system browser; it doesn't fetch the APK and silently install it (which Android would refuse anyway without the `REQUEST_INSTALL_PACKAGES` permission).

---

## Legacy

The previous Electron + Capacitor + WebSocket implementation (v1.1.0) is preserved on the [`legacy/v1`](https://github.com/tapiwamakandigona/lanlink/tree/legacy/v1) branch and tag [`v1.1.0`](https://github.com/tapiwamakandigona/lanlink/releases/tag/v1.1.0). It is not maintained; please use v2.

---

## License

MIT © [Tapiwa Makandigona](https://github.com/tapiwamakandigona)
