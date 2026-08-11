# Changelog

## 4.3.1 (+18) — UI flow polish

A pixels-first review pass over the core journeys (home -> send ->
receive -> history), fixing what a fresh pair of eyes catches.

### Fixed
- **History rows no longer lose their metadata.** The trailing action
  ("Send again" / "Retry" / "Where is it?") used to ellipsize both text
  lines; rows now use the standard card layout with the action below, and
  the size + time can never truncate.
- **Share picker:** the "Photos & videos" tab no longer clips mid-word on
  phones, and unselected media tiles drop the heavy dark chip that read as
  already-selected.
- **Settings:** the device code shows a short grouped prefix (like
  `9F2C 1E77`) with a copy button for the full value, instead of five
  wrapped lines of raw SHA-256 — and its tooltip is no longer wrong.
- **Receive:** the Same Wi-Fi / No shared Wi-Fi switch highlights the
  *selected* side with a solid accent fill; the old treatment read
  inverted.
- One word for one state: Settings now says "hidden" exactly like home,
  instead of "not receiving".
- The send screen's empty state only suggests scanning a code on devices
  that actually have a scanner.

### Improved
- **Live transfers sit above the fold.** While transfer cards are on
  screen, the big Send/Receive cards collapse to a slim row, so progress —
  including a second transfer — is visible without scrolling.
- **Recents first.** Nearby devices sort by most recent transfer, so the
  device you always send to appears first (alphabetical for new ones).
- **One-tap Open.** After a single-file receive on desktop, the card
  offers Open directly — no more dialog detour.
- "Can't see it? Get help" on the empty device list links straight to the
  connection wizard (previously buried in the overflow menu).
- "Send a message instead" moved below the device list.

## 4.3.0 (+17) — "Gauntlet"

This release folds together two lines of work: the security + hotspot
hardening that shipped as the v4.2.0 tag but never landed on `main`, and a
long polish pass across speed, usability, UI and platform support.

### Security and transport (from the 4.2.0 line)
- **HTTPS-only transport.** Every peer serves its own per-install
  self-signed certificate; connections are trusted by certificate-hash
  pinning (trust-on-first-use, then pinned), never by CA. Plain HTTP is
  gone from the wire.
- **Zero-copy sending on Android.** Files picked through the system
  document picker stream straight from their `content://` source instead of
  being copied into the cache first.
- Receiver hardening: consented-size enforcement, isolated part files per
  peer, an idle-session reaper, and disk backpressure.
- Hotspot mode: fixed transfer stalls and flaky QR connects, cancellable
  join waits, post-join readiness polling, and abortable subnet probes.

### Speed
- **Pipelined uploads** (up to 3 files in flight): ~2× faster on
  many-small-file batches over a realistic 25 ms RTT link, with single-file
  transfers unchanged.
- Rolling 5-second speed window, so live speed and ETA stop jumping.
- Announce burst on start and on every poke (0 / 400 ms / 1.2 s), plus a
  broadcast fallback and periodic multicast re-join — devices show up
  almost immediately instead of on the second scan.
- Subnet sweeps also probe the receiver's fallback ports, and an explicit
  user refresh bypasses the 20-second sweep throttle.

### Usability
- **Send a message**: type or paste a link, password or note and send it as
  a text snippet; the receiver sees it inline with a **Copy message**
  button.
- Drag and drop onto the desktop window or the Send page.
- One-tap **Open file** for single-file receives and **Open folder** for the
  rest; **Send again** on completed sends; **Clear** on the staged banner.
- History rows name the file (with its type glyph) instead of "1 file".
- The Direct Link address is a tap-to-copy chip.
- Per-type file glyphs in the picker, consent sheet and session cards.
- Low-space warning before you accept a transfer that wouldn't fit.
- Actionable errors for disk-full and permission failures, an honest
  "You're hidden — tap to retry" state, and coaching empty states.
- Ghost peers disappear from the radar after 45 s of silence.
- Button semantics for screen readers on the home verb cards.

### Reliability and platform
- Fixed a data-loss race where two same-named files uploaded in parallel
  could overwrite each other; finalization now happens under a lock with
  in-memory name reservation.
- Windows-safe filename sanitization on the receive path.
- Stale `.part` files are pruned after 7 days.
- Desktop window management: sane default size and a minimum floor.
- Toolchain: Flutter 3.44.9, Gradle 8.14.3, AGP 8.11.1, Kotlin 2.2.20,
  Android compileSdk 36; file_picker 11, mobile_scanner 7, dio 5.11.

### Known limitations
- HTTPS costs throughput on weak single-core hardware: a loopback benchmark
  in the CI-class sandbox measures ~15 MB/s for one large file versus
  ~190 MB/s over the old plain-HTTP path. Real-world Wi-Fi is usually the
  narrower bottleneck, but TLS is no longer free.
- Hotspot SSID/password are OS-randomized per session and the guest has no
  internet while joined (Android platform rule for all non-system apps).

## 4.1.0 (+15) — "Seamless Direct"

### Direct Connect — works without shared Wi-Fi
- Receive screen gains a **Same Wi-Fi / No shared Wi-Fi** switch. In Direct link mode the app hosts a LocalOnlyHotspot itself (no trip to system Settings) and bakes the credentials into the QR.
- Sender scan flow: probe the peer on the current network (~1.5 s) → if unreachable and the QR carries hotspot credentials, auto-join via WifiNetworkSpecifier (Android 10+) and continue the normal token + fingerprint pairing. Android 9 and below, iOS, and desktop guests get the SSID/password shown under the QR for manual join.
- Fixed stale pairing-guide copy referencing the removed v3 hotspot button.

### Media picker fixed + any-file sending
- Root cause of the empty media grid: the runtime permission request was never invoked. First open now shows the OS permission sheet, then the grid loads; a twice-denied state gets an inline explainer with an "Open settings" deep link.
- New **All files** tab: system document picker (any type, multi-select) — zips, APKs, PDFs, anything.

### Bidirectional sessions + disconnect
- Sessions are now symmetric: after pairing, the receiver sees the peer on the home screen with a **Send files** button — no re-scan needed. Pinned fingerprint + token trust applies in both directions.
- **Disconnect / Unpair** on the connected-peer card: notifies the peer over a bounded control route, clears session tokens on both sides, tears down the hotspot if hosting, and returns both devices to idle. Disconnect also clears the verified badge; the peer must re-pair to reconnect. The post-disconnect block is in-memory — after an app restart the peer still faces the normal consent prompt.

### Invite a friend (Android)
- Settings entry that shares the app's own APK (version-stamped) via the system share sheet — Bluetooth/Nearby/Quick Share. Falls back to a download link on split-APK installs. Receiver must allow "install unknown apps" (OS rule).

### Performance
- Eliminated rebuild storms: transfer progress ticks no longer rebuild whole pages; tighter setState scopes and selector-based listening.
- QR and theme caching, RepaintBoundary around continuously animating surfaces, builder-virtualized lists, display-size image decoding, high-refresh-rate mode on capable devices, subnet sweep throttled during active transfers.

### Known limitations (deliberate for 4.1.0)
- Hotspot SSID/password are OS-randomized per session and the guest has no internet while joined (Android platform rule for all non-system apps).
- The auto-join "Connect to device?" dialog is OS-owned and cannot be suppressed.
- Protocol security remains app-layer token + fingerprint pinning over plain HTTP; TLS is a future item.

## 4.0.0 (+14)

Complete rethink of the app on top of the v3.5 engine. One app, two verbs, hardened protocol.

### App shell — one app, two verbs
- Removed the Simple/Full mode fork and the 5-gate first-run wizard (−7,400 lines of legacy UI). One code path for everyone.
- New single-screen first run: pick a name, go.
- New home: **Send** and **Receive** as the only two top-level verbs, with grouped transfer cards below (dismiss, cancel, retry, "Clear finished").
- **Receive** shows a QR code instantly (one-time connect token, auto re-minted when redeemed or when the app resumes) with a Direct Link fallback.
- **Send** has exactly three connect paths: device radar, QR scan, Direct Link (paste an address).
- "Where is it?" on completed receives opens the saved folder path with copy-to-clipboard.
- Incoming transfers use a bottom consent sheet with an optional "Always accept from this device" trust checkbox (only offered when the sender is locally resolvable, pinned by fingerprint — never by claimed identity).

### Design — Ember on Paper
- New v4 design system (`lib/ui/v4/`): warm paper surfaces, copper accent, dedicated tokens for spacing, radius, type, motion, and QR presentation; light + dark.
- New components: TwoVerbHome, DeviceRadar, SessionCard, ConsentSheet, QR display/scan frames, Verified badge.

### Security & protocol hardening
- Upload tokens are single-use: replayed upload requests get 401.
- Connect tokens: only the newest minted token is valid; old QR codes stop working the moment a new one is shown or redeemed.
- Fingerprint pinning with a local-only `verified` flag (never serialized to the wire); consent re-resolves the sender locally.
- Rejected and post-abort uploads drain at most 32 MB before the connection is terminated (DoS bound), pre-stream and mid-stream.
- Radar taps resolve targets by device fingerprint, not display name — alias collisions can no longer misdirect a transfer.
- Bidirectional cancel (`POST /cancel`) and defensive handling of malformed send/prepare-upload requests.
- Live port announcements; settings null-safety fixes.

### UX fixes from review
- Direction-aware transfer labels (Receiving / Received! / "from X").
- "Try again" only shows when a retry is actually possible; failed receives no longer show a dead button.
- Receive page: Retry button when the receiver is unavailable; QR re-mints automatically after redemption.
- Connecting spinner while QR/Direct Link connections are in flight.
- IPv6 addresses in Direct Link are rejected with a clear message instead of a silent failure.

### Known limitations (deliberate for 4.0.0)
- Hotspot hosting (offline transfers) from v3 is not yet reinstated.
- Device nicknames are read-only.
- Screenshot suite renders but has no pixel-level assertions yet.

Test suite: 208 tests, all passing.

## 3.5.0 (+13)
- Last v3 release. Baseline for the v4 rebuild.
