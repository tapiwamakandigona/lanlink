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

Surface order = priority order. Tick when done. Locked design decisions in
**bold**.

- [ ] **First-run + post-update onboarding slides.** 4–5 Flutter-rendered
  carousel slides (no PNG assets — we redraw the real UI with arrows /
  tooltips so they stay in sync). Skip button + "Got it" on the last
  slide. Triggered on first launch and once after every version bump
  (compare stored `last_seen_version` against `package_info_plus`).
  **Decision: Flutter-rendered (Tapiwa confirmed).**
- [ ] **"?" help button on home page.** Opens a sheet that links into the
  same slides + a tiny FAQ.
- [ ] **Idle help nudge.** If the user has been on the home page for ~30s
  without picking a peer / opening the sender, surface a small "Need
  help getting started?" banner that opens the help sheet.
- [ ] **Hotspot becomes the default connectivity mode** on Android.
  iOS / macOS / Windows keep LAN as default (see "hotspot-first
  platform split" below).
- [ ] **New "Are you sending or receiving?" guided flow.** Full-screen
  landing that replaces the home page on launch (Option 1: dramatic
  Setup-Assistant style — **Tapiwa confirmed**). Two big cards:
  - **Receive**: shows our pair QR + (Android) a "Turn on your hotspot"
    button that deep-links into Settings, plus instructions. We poll
    network interfaces for `192.168.43.0/24` / `192.168.49.0/24` and
    flip the card to "Ready — ask them to scan" when we see one.
  - **Send**: opens the scanner, then drops them on the file picker.
  Hotspot-first only on Android; iOS / Mac / Windows users can still
  send via this flow (they just join the Android side's hotspot from
  their Wi-Fi settings before scanning the QR).
- [ ] **Cancel button on the per-session sheet** (already exists — make
  sure it's prominently surfaced in the new sender flow).
  **Decision: pause/resume dropped (Tapiwa confirmed). Cancel-only.**

## Known constraints / things to discuss

### Hotspot-first platform split
**Tapiwa's decision:** Hotspot becomes the default on Android. iOS /
macOS / Windows keep LAN as the default. iOS users can still **send**
via the new flow — they join the Android side's hotspot from their
Wi-Fi settings, scan the QR, transfer. iOS can't reliably **host** a
hotspot programmatically (no public API), so we don't pretend
otherwise.

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
**Tapiwa's decision: not shipping pause/resume.** Only Cancel.
The LocalSend v2 protocol doesn't expose a byte-offset resume and the
cost of faking it (restart files from 0 on resume) was deemed not worth
the UI complexity. Cancel already works — we just need to make sure it's
obvious in the new sender flow.

### Onboarding screenshots
**Tapiwa's decision: Flutter-rendered.** Onboarding slides are small
Flutter widgets that draw the real UI + yellow arrows / tooltips, sharing
the same theme as the running app. No PNG assets, no APK growth, slides
stay current as the UI changes.

---

## Backlog / future ideas

**v3.1.0 selected from suggestion round (Tapiwa picked):**
- [ ] Permission priming on first run — request notification + local-network
  + camera permissions upfront in the onboarding flow, not mid-transfer.
- [ ] System share-sheet integration — register LanLink as a target for
  Android `ACTION_SEND` / `ACTION_SEND_MULTIPLE` so users can hit
  "Share → LanLink" from Photos / Files. iOS share extension later.
- [ ] Retry button on failed / cancelled transfers — history entry gets
  a "Retry" action that re-stages the same files to the same peer.
- [ ] Drag-and-drop on macOS / Windows — drop files onto the window to
  pre-stage them for the next send.
- [ ] Proper app icons + splash for iOS / macOS — v3.0.0 still has default
  Flutter icons on those platforms.
- [ ] Friendly error messages — map `SocketException`, `TimeoutException`,
  HTTP 4xx/5xx to plain English ("Couldn't reach Tapiwa's phone — make
  sure both phones are on the same hotspot").
- [ ] Expand hotspot subnet detection — add Samsung `192.168.45.0/24` and
  other OEM ranges beyond the current `.43` / `.49`.
- [ ] Local-only crash / event log — ring buffer of last ~200 log lines
  with a "Copy to clipboard" button in Settings for support.

**Deferred / not selected:**
- Beta update channel (skipped — keep stable-only for now).
- End-to-end encryption / TLS for the wire (skipped for v3.1.0 — the
  LAN-only model already limits exposure).
- Background transfers on iOS via BGTaskScheduler / URLSession (Swift
  rewrite needed for true background).
- Apple Push, Apple Developer signing for iOS/Mac, localisations,
  per-session bandwidth cap. All out of scope for now.

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
