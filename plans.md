# LanLink — shared plans / scratchpad

Living document. Maintained by Tapiwa + whatever AI assistant is driving the
session. New assistants should read this top-to-bottom before doing anything.

---

## What has shipped so far

| Version | Headline change |
|---------|----------------|
| v1.x    | Original Flutter rewrite, basic LAN file send/receive. |
| v2.0.0-rc.2 | Production sharing modes + branding. |
| v2.0.1  | Hotspot role picker, subnet scan, manual refresh, update checker. |
| v2.0.2  | README + dismissible "update available" banner, "Check for updates" tile. |
| v2.0.3  | QR pairing, per-peer nicknames, fan-out send, per-peer history. |
| v2.0.4  | Polished dark mode + animated transfer outcome chip. |
| v2.0.5  | Android system notifications with progress. |
| **v3.0.0** | macOS + iOS apps, Android background transfers (foreground service), persistent transfer history, APK shrink (R8 + per-ABI splits), UX moves ("Made by..." → Settings, "Check for updates" off About). |

Latest release: https://github.com/tapiwamakandigona/lanlink/releases/tag/v3.0.0

---

## Codebase map (Flutter, single repo)

```
lib/
  main.dart                       entry point; bootstraps AppState
  app.dart                        MaterialApp + global incoming-prompt wiring
  state/
    app_state.dart                THE central ChangeNotifier. Holds sessions,
                                  peers, settings, history; wires sender +
                                  receiver + discovery + foreground service.
  core/
    protocol/constants.dart       LocalSend v2 wire constants (/api/...).
    models/
      device.dart                 Peer record (alias, fingerprint, ip, port).
      file_info.dart              One file's metadata.
      session.dart                TransferSession + FileProgress + JSON
                                  snapshot helpers used by history.
    transfer/
      sender.dart                 Outbound HTTP client (dio).
      receiver.dart               Inbound shelf server + accept prompt +
                                  MediaStore publish on Android 10+.
    discovery/
      multicast.dart              UDP multicast announce + listen.
      subnet_scanner.dart         /24 sweep for hotspot mode.
    history/
      transfer_history_store.dart SharedPreferences-backed, 200-entry cap,
                                  250ms debounce on save.
    platform/
      foreground_service.dart     Dart bridge to Android FG service.
      transfer_notifications.dart Per-session progress notification (Android).
      platform_share.dart         Bluetooth share fallback (Android only).
      android_apps.dart           List installed apps for "send an APK" UX.
    settings/app_settings.dart    SharedPreferences settings (theme,
                                  trusted peers, save dir, nicknames).
    update/update_checker.dart    GitHub releases polling + ReleaseInfo.
    connectivity/connectivity_mode.dart  LAN / Hotspot / Bluetooth enum.
  ui/
    splash_gate.dart              Splash → onboarding (TODO) → home.
    home_page.dart                Tabbed: Peers / Transfers / History.
    settings_page.dart            All settings; hosts the update tile.
    about_page.dart               Version + credit + license info.
    history_page.dart             History list + Clear button.
    scan_qr_page.dart             Camera QR scanner (mobile_scanner).
    show_qr_page.dart             Render our pair QR.
    widgets/*                     Reusable widgets (peer tile, status chip,
                                  receive dialog, update banner, etc.)
android/  Native bits: MainActivity, TransferForegroundService, TransferNotifier.
ios/      Scaffolded in v3.0.0. Info.plist has Bonjour + local-network keys.
macos/    Scaffolded in v3.0.0. Entitlements include network.client/server +
          files.user-selected.read-write + files.downloads.read-write.
windows/  Standard Flutter Windows shell.
```

Key invariants worth not breaking:
- `TransferSession` is a `ChangeNotifier`; never replace one with a new
  instance mid-transfer (UI subscribers will drop their listeners). Mutate
  in place. The send pipeline relies on this.
- Per-peer state is keyed by **fingerprint**, never alias / IP. Aliases and
  IPs can change at any moment.
- Only terminal sessions (`completed` / `failed` / `cancelled`) are
  persisted to history. In-flight sessions stay in memory.
- The receiver writes to a temp file first and only republishes to
  Downloads/LanLink after the upload completes successfully.

---

## Active asks from Tapiwa (v3.1.0 candidates)

Surface order = priority order. Tick when done.

- [ ] **First-run + post-update onboarding slides.** 4–5 carousel slides with
  in-app screenshots + arrows, "Skip" button, "Got it" on the last. Show
  on first launch ever, plus once after every version bump (compare stored
  `last_seen_version` against running version in `package_info_plus`).
- [ ] **"?" help button on home page.** Opens a sheet that links into the
  same slides + "Email Tapiwa" + a 1-line "common problems" FAQ.
- [ ] **Idle help nudge.** If the user has been on the home page for ~30s
  without picking a peer / opening the sender, surface a small "Need
  help getting started?" banner that opens the help sheet.
- [ ] **Make Hotspot the default connectivity mode.** Today the default is
  LAN; switch to Hotspot. Keep LAN + Bluetooth as picker options.
- [ ] **New "Are you sending or receiving?" guided flow.** A big landing
  screen with two cards:
  - Receiver: shows our pair QR + (Android) a "Turn on your hotspot"
    deep-link button into `Settings.Panel.ACTION_INTERNET_CONNECTIVITY`
    or `WIFI_TETHER_SETTINGS`. The pair QR already encodes
    `ip / port / alias / fingerprint`; sender will join the hotspot,
    scan the QR, and we land in the existing peer-handshake path.
  - Sender: opens the scanner, then drops them on the file picker.
- [ ] **Pause / Resume / Cancel** on the per-session sheet. Cancel exists;
  pause is new and has to be designed carefully because the LocalSend v2
  protocol doesn't have a `pause-upload` verb. See "Constraints" below.

## Known constraints / things to discuss

### Hotspot auto-on is not possible
- **Android:** since 8.0 (Oreo) `WifiManager.startTethering()` / SoftAp
  APIs require the system-only `TETHER_PRIVILEGED` permission. No
  third-party app can turn the personal hotspot on programmatically.
  Best we can do: deep-link to `Settings → Network → Hotspot`. On most
  OEMs the right intent action is one of
  `Settings.ACTION_WIRELESS_SETTINGS` or
  `com.android.settings$TetherSettingsActivity` (component intent — OEM
  specific). We'll fall back through a few of these.
- **iOS:** Personal Hotspot is not exposed via any public API at all.
  Best we can do: prompt the user to open Control Center.
- **Implication:** the receiver flow becomes "Show QR + a big 'How to
  turn on your hotspot' card + a 'Hotspot is on, ready' button the user
  taps when they've actually toggled it. The button just kicks the
  multicast / subnet announce so the sender finds us."

### Pause / resume on the wire
- LocalSend v2 uses one HTTP POST per file (multipart). We can:
  - **Cancel** by aborting the dio request and `markStatus(cancelled)`.
    (Already implemented.)
  - **"Pause"** by cancelling on the wire, but keeping the
    TransferSession alive in a new `paused` status so the user can
    "Resume", which kicks off a fresh `prepare-upload` for the remaining
    files. Files already fully uploaded stay uploaded; files
    half-uploaded restart from byte 0 (no protocol resume). For most
    users this is OK because LAN transfers are fast.
  - True resume from a byte offset is **out of scope** without
    extending LocalSend v2 with a non-standard header.

### Onboarding screenshots
We have two options:
1. **Render synthetic screenshots in-Flutter** at slide time (cheaper —
   no PNG assets, easy to keep up to date). Slides become little Flutter
   widgets that draw stylised UI + arrows.
2. **Real PNG screenshots** captured on a phone and bundled as assets.
   Higher fidelity, bigger APK (~5–10 MB more), harder to maintain when
   the UI changes.

Recommendation: option 1, with the same fonts / Material 3 widgets the
real app uses. Onboarding stays in sync automatically.

---

## Backlog / future ideas

- Background transfers on iOS — currently iOS will suspend us within ~30s
  of backgrounding. Realistic options: `BGTaskScheduler` for "finish
  what's in flight" with hard 30-second budget; or `URLSession` background
  transfers which would require a Swift-side rewrite of the upload path.
- Apple Push for "device available" cross-network — out of scope; the
  whole point of LanLink is no cloud.
- Real signing for iOS / Mac releases (Apple Developer account + secrets).
- Localise into one or two additional languages (we deliberately stripped
  locales in v3.0.0 to shrink the APK; reintroducing one is fine).
- Optional encryption-at-rest of received files until the user opens them.
- Per-session bandwidth cap.

## Known bugs / quirks (as of v3.0.0)

- macOS first launch may show the local-network permission prompt twice
  (system bug, not ours). Subsequent launches behave.
- On Android 8 (very old), the foreground-service `dataSync` type is
  ignored and the service degrades to a normal foreground service. Still
  works; just no special OS treatment.
- iOS unsigned `.ipa` cannot be installed without AltStore / Sideloadly
  + a free Apple ID; this is fundamental, not a bug, but document it
  clearly in the release notes.

---

## How to use this file

- **Tapiwa**: edit freely on GitHub or via PRs. Add notes, gripes,
  reordered priorities, screenshots of bugs.
- **AI assistants (any model)**: read this file as your first action in a
  new session. Reflect any decisions made during the session back into
  this file before opening a PR. Don't silently drop entries from the
  "Active asks" list — strike them through with `~~text~~` once a PR is
  merged that addresses them.
