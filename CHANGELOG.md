# Changelog

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
