# LanLink architecture

This document captures the decisions behind the LanLink v2 rewrite — what we chose, what we considered, and what we deliberately deferred. It complements the high-level overview in [`README.md`](../README.md).

## Background

LanLink v1 was an Electron + Capacitor app that relied on WebSocket message-passing through a desktop "hub". This had three root problems that couldn't be patched away:

1. **Base64-over-JSON file chunks.** Every chunk was JSON-wrapped, base64-encoded, and pushed through React state on the receiver. Memory usage scaled linearly with file size — multi-gigabyte transfers were never going to work.
2. **Asymmetric topology.** The desktop ran a WebSocket *server*; mobile devices were *clients*. Phone-to-phone transfers required a desktop to be on and acting as relay.
3. **Fragile discovery.** Discovery used UDP `/24` broadcast, which is filtered by many home routers and enterprise APs. mDNS would have been more robust.

## Goals for v2

- **Cross-platform from one codebase**: Android 8+, iOS 12+, Windows 10/11, macOS 10.15+, and Linux.
- **Symmetric peers**: every device is both sender and receiver.
- **Streaming I/O**: constant memory regardless of file size.
- **No internet required**: pure LAN, no relays, no accounts.
- **CI artifacts on every PR** so you can sideload-test without a local toolchain.

## Decisions

### Framework: Flutter

We chose Flutter over the alternatives because it:

- **Targets both Windows and Android natively** from one Dart source tree (no JavaScript bridge to mobile).
- Has a mature **`shelf`** HTTP-server ecosystem and **`dio`** HTTP client with first-class streaming and multipart support.
- Provides **`dart:io`** raw sockets, which gives us direct UDP multicast for discovery without platform plugins.
- Compiles to ahead-of-time native binaries on both platforms (small, fast, no JIT warm-up).

Alternatives considered:

| Stack | Why not |
|---|---|
| Electron + Capacitor (v1) | Heavy on RAM, awkward mobile story, two languages, no AOT compilation. |
| React Native + Tauri | Two separate frameworks with two separate native bridges. Sharing code is doable but glue-heavy. |
| .NET MAUI | Mature, but Windows-strong / Android-weaker. Less obvious LAN-protocol library coverage. |
| Kotlin Multiplatform | UI must be written twice (Compose + Compose Multiplatform on desktop is still maturing). |
| Pure native (Kotlin + WinUI 3) | Best per-platform UX, but doubles the surface area and rules out a small-team rewrite. |

### Wire protocol: LocalSend v2

We adopted [LocalSend v2](https://github.com/localsend/protocol) verbatim instead of designing our own protocol. Concretely this means:

- HTTP over the LAN with a fixed default port (`53317`).
- A small set of `/api/localsend/v2/*` endpoints (see the table in the README).
- A two-phase upload: a JSON manifest in `prepare-upload`, then raw-bytes `upload` requests, one per file.
- UDP multicast announcements on `224.0.0.167:53317` carrying the same `info` payload as the HTTP `/info` route.

Benefits:

1. We get **free interop with LocalSend itself** — useful as a sanity check during testing and useful for users who already have LocalSend on a device.
2. The protocol is **already-debugged**, with five years of cross-platform deployment behind it.
3. The contract is **JSON + raw bytes**, no esoteric framing, easy to reason about and easy to fuzz.

### Discovery: UDP multicast primary, manual fallback

We chose UDP multicast on `224.0.0.167:53317` as the primary mechanism because:

- It's the native LocalSend mechanism, so we get interop for free.
- `dart:io` supports it directly with no platform plugins on either Android or Windows.
- It works on most home networks; consumer routers usually permit multicast within a subnet.

We considered mDNS as well (and `multicast_dns` is in our dependency tree for a future enhancement), but in practice mDNS on Android requires `NSDManager` plumbing and is finicky across vendor builds. Adding it as a second discovery layer is a follow-up.

For networks where multicast is filtered entirely (some enterprise/guest networks), the Home screen has an **Add device by IP** action that performs an HTTP `/info` probe against a user-typed `host:port`.

### Transfer: stream-based HTTP, no base64

The sender opens the file on disk as a `Stream<List<int>>`, hands it to `dio.postUri` as the request body, and `dio` writes it straight to the socket. The receiver's `shelf` handler reads `req.read()` (also a `Stream<List<int>>`) and pipes it into a `RandomAccessFile` opened on the destination. Neither side ever holds the full file in memory.

We deliberately do **not** use:

- **Base64**, which inflates the wire payload by ~33% and forces a decode pass.
- **Chunked JSON messages**, which would re-introduce the heap pressure that killed v1.
- **WebSocket framing** for bulk transfer, which adds per-frame overhead and complicates back-pressure.

### State management: `ChangeNotifier` + Provider

Top-level state is a single `AppState` (`ChangeNotifier`) that owns the receiver, the sender, the discovery service, and the lists of peers and sessions. UI screens subscribe via `provider`'s `ChangeNotifierProvider.value` and `context.watch<AppState>()`.

We considered `riverpod`, `bloc`, and `flutter_redux`. All would work, but for a project this size the indirection cost outweighs the testability/scaling wins. Plain `ChangeNotifier` keeps the dependency list short and the data flow obvious.

### Persistence: SharedPreferences

Settings (alias, save folder, trusted fingerprints, quick-save toggle, port override) live in `SharedPreferences`. The data is small (a handful of keys), and the plugin is supported on every Flutter target. We avoided pulling in a full SQLite layer (`drift`, `sqflite`) until we have a feature that needs it (e.g. a persistent transfer history).

In-app transfer history is now persisted across restarts via `TransferHistoryStore`, which serialises terminal-state sessions to `SharedPreferences` (debounced, capped at 200 entries). The `AppState` reloads them on startup. A future migration to `drift` would mainly add query flexibility and relational indexing — not needed yet.

### Build + CI

- **CI (`.github/workflows/ci.yml`)** runs on every pull request and push to `main`. Five jobs: `analyze-and-test` (formatting + static analysis + unit tests), `build-android` (debug APK), `build-windows` (release zip), `build-macos` (release zip), and `build-ios` (unsigned .app). Artifacts are uploaded so reviewers can sideload them without a local toolchain.
- **Release (`.github/workflows/release.yml`)** runs on tags matching `v*`. It produces signed release APKs (per-ABI splits + universal, using either repository-secret keystore values or a CI-generated keystore as a fallback), a Windows NSIS installer, a macOS .dmg, a Linux AppImage + tar.gz, and an unsigned iOS .ipa. All assets are attached to a GitHub Release and mirrored to the public `lanlink-downloads` repo.
- Flutter is pinned to **3.24.5 (channel stable)** in both workflows for reproducibility; bump it in both files when upgrading.

The release APK keystore handling deserves a note: we prefer real signing keys (`SIGNING_KEY_BASE64`, `SIGNING_STORE_PASSWORD`, `SIGNING_KEY_ALIAS`, `SIGNING_KEY_PASSWORD` repo secrets), but fall back to a fresh CI-generated keystore if those secrets aren't configured. This keeps the workflow green out of the box, at the cost of stable upgrades (Android will refuse to upgrade an APK whose signer changed). Production-quality releases should set the secrets.

## Risks and follow-ups

These are deliberately deferred from v2.0; they are tracked here so they aren't forgotten.

1. **TLS + fingerprint pinning.** LocalSend v2 supports HTTPS with self-signed certificates and trust-on-first-use. We ship HTTP-only for v2.0 to keep cert generation out of the critical path; the Sender/Receiver classes already speak the URL-scheme abstraction, so adding TLS is a self-contained change.
2. **mDNS** as a second discovery layer for networks that allow mDNS but block link-local multicast.
3. ~~**Background receiving on Android.**~~ ✅ Resolved — `TransferForegroundService` (Kotlin) keeps the process alive during transfers with `foregroundServiceType="dataSync"` declared in the manifest. Per-session progress notifications are posted by `TransferNotifier`.
4. ~~**Persistent history**~~ ✅ Resolved — `TransferHistoryStore` persists sessions to `SharedPreferences` (see Persistence section above).
5. **Real production code-signing certs** on both platforms (Play Store upload key for Android, EV cert for Windows). v2.0 ships unsigned installers and CI-keystore APKs to unblock sideload testing.
6. ~~**App icon and branding.**~~ ✅ Resolved — custom LanLink icons are in place across all platforms.
