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
| v3.1.0  | Onboarding slides, help/pairing guide, friendly errors, retry on failed transfers, diagnostics log, update checker pointed at the public lanlink-downloads mirror. |
| v3.2.0  | Pairing wizard, plain-English ETA, slow-network warning, share-sheet target, drag-and-drop, idle nudge, success celebration, glossary tooltips, help footer, file thumbnails, connection-quality indicator. |
| v3.3.0  | Simpler home UI (menu app bar, one-line mode status, single Send button, no forced wizard); Linux release builds (AppImage + tar.gz); release mirroring to lanlink-downloads + tapiwa.me downloads. |
| **v3.4.0** | The "one big update": Simple mode for non-technical users, new LL circuit-monogram app icon (option D), one-tap Direct Link (auto hotspot + Wi-Fi QR on Android), resumable transfers (mid-file), whole-folder sending with structure preserved, SHAREit-style share picker (photo/video grid with thumbnails + apps-as-APK tab with icons & search), one-tap "Move my photos" camera-roll migration, real release signing (uninstall/reinstall once coming from ≤v3.3.0). |

Latest release: https://github.com/tapiwamakandigona/lanlink/releases/tag/v3.4.0

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

## v3.4.0 decisions (locked, shipped this session)

- **One big update** — Tapiwa asked to hold the release until all the
  planned features landed, instead of splitting v3.4/v3.5. Done.
- **Icon: option D** (LL circuit monogram) across all platforms.
- **Auto-hotspot + QR ("Direct Link")** approved as the best-approach for
  phone-to-phone connectivity on Android (localonly hotspot API, QR embeds
  SSID + password + host IP).
- **Share picker**: tabs Photos & videos · Apps, thumbnail grid, search,
  multi-select with a running "N items • X MB" total. APKs of installed
  apps can be sent; **OBB expansion files are mostly impossible on
  Android 11+ and app private data is impossible without root** — not
  shipped, by design.
- **"Move my photos"**: one-tap camera-roll migration — stages every
  photo/video from the camera roll under `My photos/` after a single
  confirmation dialog showing counts + total size.
- **Simple mode** has a "Full version" escape button; can be hidden by a
  caregiver from Settings.
- **Resume transfers**: receiver advertises byte offset, sender continues
  mid-file; stale offsets get 409 and a clean restart.
- **Folder sending**: relative paths preserved end-to-end.
- **Release signing**: real RSA-4096 keystore (secrets in GitHub Actions,
  backup in Tapiwa's Google Drive "LanLink Release Keys"). Users on
  ≤v3.3.0 must uninstall/reinstall once (CI keystore → real keystore).
- **No iOS dev account** — unsigned .ipa stays sideload-only.
- Golden walkthrough tests (`test/walkthrough_screenshots_test.dart` +
  `test/goldens/`) double as release screenshots; regenerate with
  `flutter test --update-goldens` on Linux when UI changes.

---

## Active asks from Tapiwa (v3.1.0 candidates — all shipped in v3.1.0/v3.2.0)

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

**UI/UX picks Tapiwa selected (v3.1.0):**
- [ ] Estimated time left ("About 30 seconds left") instead of just %.
- [ ] Replay-tutorial button in Settings.
- [ ] First-time success animation (confetti / checkmark).
- [ ] File thumbnails next to progress bar during transfer.
- [ ] Plain-language status chips ("Got it ✓", "Stopped", "Didn't work — tap to retry").
- [ ] Connection-quality indicator (Wi-Fi-style bars) in the AppBar.
- [ ] Glossary tooltips (ⓘ icons) on jargon in Settings.
- [ ] "Send another?" prompt after a successful send.
- [ ] Slow-network warning (<100 KB/s for 5s → "Move closer").
- [ ] "I've used apps like this before" wording on the Skip button.
- [ ] Drop technical jargon from user-facing UI (MDNS, multicast, fingerprint).
- [ ] "Need help?" footer on every screen except home (home has floating ?).

**Deferred / not selected:**
- Beta update channel (skipped — keep stable-only for now).
- End-to-end encryption / TLS for the wire (skipped for v3.1.0 — the
  LAN-only model already limits exposure).
- Big-button "easy" mode (deferred — accessibility revisit later).
- Success chime + vibrate (deferred).
- Dark mode = follow system default (deferred — already a setting).
- Background transfers on iOS via BGTaskScheduler / URLSession (Swift
  rewrite needed for true background).
- Apple Push, Apple Developer signing for iOS/Mac, localisations,
  per-session bandwidth cap. All out of scope for now.

---

## Device-pairing wizard (Tapiwa's idea — locked in for v3.1.0)

After splash, **before** any peer list, the app runs a 3-step wizard:

**Step 1 — Direction.** "What do you want to do?"
  - Send something
  - Receive something

**Step 2 — Other device.** "What kind of device is the other person using?"
  - Android phone / Tablet
  - iPhone / iPad
  - Windows PC
  - Mac
  - Not sure

The app already knows **its own** platform via `Platform.is*`. Combining
self + direction + other resolves to one of 16 unique pairings.

**Step 3 — Tailored instructions.** A single screen with the exact steps
for that pairing, no edge cases shown to the user. Per pairing:

| Sender → Receiver | Receiver action | Sender action |
|---|---|---|
| Android → Android | Turn on hotspot (deep-link). Show QR. | Join hotspot from Wi-Fi → scan QR. |
| Android → iPhone | Join Android sender's hotspot from iPhone Wi-Fi settings. | Turn on hotspot (deep-link). Show QR after iPhone joins. |
| Android → Mac/Win | Make sure Mac/PC is on same Wi-Fi. | Same Wi-Fi → auto-discovered, no QR. |
| iPhone → Android | Turn on hotspot (deep-link). Show QR. | Join hotspot from iPhone Wi-Fi → scan QR. |
| iPhone → iPhone | Manually enable Personal Hotspot from Control Center. Show QR. | Join hotspot manually → scan QR. |
| iPhone → Mac/Win | Same Wi-Fi. | Same Wi-Fi → auto-discovered. |
| Mac/Win → Android | Same Wi-Fi router. | Same Wi-Fi → auto-discovered. |
| Mac/Win → iPhone | Same Wi-Fi router. | Same Wi-Fi → auto-discovered. |
| Mac/Win → Mac/Win | Same Wi-Fi router. | Drag-and-drop window. |
| Anything → "Not sure" | Show both options ("If they're on the same Wi-Fi as you, tap Auto-find. Otherwise, ask them to show their QR code"). | Same. |

**Memory.** After a successful transfer, remember the pairing
("last_pairing": `android_to_android_via_hotspot`). On next launch the
wizard offers a "Same setup as last time" shortcut.

**Power-user escape hatch.** A small "I know what I'm doing — skip
wizard" link on Step 1 jumps straight to the legacy peer list home.

## User flows after v3.1.0 ships

These are what we're building toward. Each flow assumes the v3.1.0
onboarding + Receive/Send landing is in place. "Hotspot" means
phone-tethered Wi-Fi; "LAN" means an existing Wi-Fi router.

### Phone-to-phone (Android → Android, the headline flow)
**Receiver:** open app → "Receive". Card shows our pair QR + a big
button "Turn on your hotspot". Tap → OS hotspot settings open → toggle
hotspot on → return to app. App polls network interfaces, detects the
hotspot is up, flips card to "Ready — ask them to scan this QR".
**Sender:** open app → "Send". App opens Wi-Fi settings if they're not
yet on the receiver's hotspot. They join the hotspot from Wi-Fi
settings → return → camera opens → scan QR → file picker → pick files →
transfer starts. Cancel button is always visible. On success, "Send
another?" prompt.

### Android (sender) → iPhone (receiver)
Not supported as receiver-hosts — iOS can't host a hotspot from inside
LanLink. Flow flips: iPhone joins the Android phone's hotspot or any
shared Wi-Fi, Android sends. Onboarding explains this — "If you're
using an iPhone to receive, ask the Android person to host the hotspot
instead."

### iPhone (sender) → Android (receiver)
Android hosts the hotspot as above. iPhone joins from
Settings → Wi-Fi → tap the Android hotspot SSID. Then iPhone opens
LanLink → "Send" → scans the Android's QR → picks files. Works
end-to-end. The QR is the bridge — no manual IP typing.

### Phone → Mac / PC, or Mac / PC → Phone
Mac/PC keeps LAN as default. Both devices need to be on the **same
Wi-Fi network** (a regular router, not a phone hotspot — Mac/PC don't
have hotspot toggles easily). The Mac/PC shows up in the peer list
automatically via multicast. Phone user opens "Send" → peer list (no
QR needed because multicast discovery already found them) → pick
files. For cross-network edge case (Mac on Ethernet, phone on Wi-Fi
that bridge), the user can fall back to scanning the Mac's QR.

### Mac ↔ Mac, Windows ↔ Windows, Mac ↔ Windows
Standard LAN mode. Both on same Wi-Fi → drag files onto the window
(post-v3.1.0 drag-and-drop feature) → peer list shows the other
machine → click → send. No QR needed unless multicast is blocked.

### iPhone ↔ iPhone
Awkward case. Neither can host a hotspot programmatically. Two options:
1. Both on the **same Wi-Fi router** → standard LAN mode, multicast
   discovery, works fine.
2. One iPhone enables Personal Hotspot from Control Center
   manually, the other joins; from LanLink's perspective this is the
   same as Android-host flow. Onboarding documents this.

### Edge cases handled by v3.1.0
- Permission denials at first run → onboarding re-asks with explanation.
- Hotspot subnet not in our known list → expanded list (Samsung .45,
  Xiaomi, etc.) covers the long tail.
- Slow link → user gets a "move closer" hint instead of staring at a
  stuck progress bar.
- Transfer fails partway → status chip says "Didn't work — tap to
  retry"; history entry has Retry button.

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


## v3.4.1
- Simple-mode Direct Link, first-run mode chooser, fast picker, move-photos progress.
