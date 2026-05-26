# LanLink

> Fast, reliable LAN file sharing between Windows and Android. Same Wi-Fi, no internet, no account, no cloud.

LanLink is a single Flutter codebase that runs on **Android 8+** and **Windows 10/11**. Every running instance hosts its own HTTP server and announces itself on the local network, so transfers are peer-to-peer — PC ↔ phone, phone ↔ phone, and phone ↔ PC all work the same way.

LanLink speaks the [LocalSend v2 wire protocol](https://github.com/localsend/protocol), so LanLink can also interoperate with LocalSend out of the box.

---

## Features

- **Peer-to-peer LAN transfers.** No central server, no cloud relay, no internet required.
- **Symmetric topology.** Phones can send to PCs, PCs to phones, and phones to phones — every device is both a sender and a receiver.
- **Stream-based file I/O.** Files go straight from disk → network → disk; memory usage stays flat regardless of file size. Multi-gigabyte transfers work fine.
- **UDP-multicast discovery** on `224.0.0.167:53317`, with **manual IP entry** as a fallback for hostile networks.
- **Per-transfer accept prompt** so random devices on your network can't dump files on you. Optionally mark senders as **trusted** for one-tap acceptance next time.
- **Cross-platform UX** that follows platform conventions (Material 3 light/dark, system theme).
- **Reproducible CI builds**: every PR produces a downloadable debug APK + Windows zip, and tags produce a signed release APK + NSIS installer.

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

### Transfer

LanLink follows the [LocalSend v2 HTTP protocol](https://github.com/localsend/protocol):

| Endpoint | Direction | Purpose |
|---|---|---|
| `GET /api/localsend/v2/info` | Either | Returns the device's `alias`, `version`, `deviceModel`, `deviceType`, `fingerprint`, `port`, and `protocol`. |
| `POST /api/localsend/v2/register` | Either | Lets a peer announce itself unicast and receive `info` back. |
| `POST /api/localsend/v2/prepare-upload` | Sender → receiver | Body contains `info` + a `files` manifest. Receiver shows a prompt; on accept, replies with a `sessionId` and a per-file `token`. |
| `POST /api/localsend/v2/upload?sessionId&fileId&token` | Sender → receiver | Body is the raw file bytes (no base64). Receiver streams them straight to disk via a `.part` temp file, then atomic-renames into the save folder. |
| `POST /api/localsend/v2/cancel?sessionId` | Either | Aborts an in-progress session. |

### Security model

- v2.0 ships **HTTP only** (no TLS). All traffic stays on the LAN.
- Every incoming transfer triggers an in-app **Save / Decline** prompt unless the sender's fingerprint is in your **Trusted devices** list and **Quick Save** is enabled.
- Per-file `token`s are random UUIDs scoped to one session; uploads that miss the token are rejected.
- A TLS layer with per-install self-signed certificates and fingerprint-pinning is a planned follow-up (see [`docs/architecture.md`](docs/architecture.md) → "Risks and follow-ups").

### Repo layout

```
lanlink/
├── lib/
│   ├── core/
│   │   ├── discovery/        # UDP multicast announce + listen
│   │   ├── models/           # Device, FileInfo, TransferSession
│   │   ├── protocol/         # Wire constants + route names
│   │   ├── server/           # (reserved for future TLS layer)
│   │   ├── settings/         # AppSettings (SharedPreferences-backed)
│   │   ├── transfer/         # Sender (dio) + Receiver (shelf)
│   │   └── util/             # network, fingerprint, formatting
│   ├── state/
│   │   └── app_state.dart    # Top-level ChangeNotifier
│   └── ui/
│       ├── home_page.dart
│       ├── settings_page.dart
│       ├── history_page.dart
│       └── widgets/          # DeviceCard, ProgressCard, ReceivePromptDialog
├── android/                  # Flutter Android runner (minSdk 26)
├── windows/                  # Flutter Windows runner
├── docs/architecture.md      # Architecture decision record
├── test/widget_test.dart     # Unit tests
└── .github/workflows/
    ├── ci.yml                # PR + main: analyze, test, build APK + Windows zip
    └── release.yml           # Tag v*: signed APK + NSIS installer + GitHub Release
```

---

## Legacy

The previous Electron + Capacitor + WebSocket implementation (v1.1.0) is preserved on the [`legacy/v1`](https://github.com/tapiwamakandigona/lanlink/tree/legacy/v1) branch and tag [`v1.1.0`](https://github.com/tapiwamakandigona/lanlink/releases/tag/v1.1.0). It is not maintained; please use v2.

---

## License

MIT © [Tapiwa Makandigona](https://github.com/tapiwamakandigona)
