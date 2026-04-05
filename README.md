# 🔗 LanLink

> Fast, local file transfer and messaging between your PC and phone over WiFi. No internet required.

![LanLink Banner](docs/screenshots/banner-placeholder.png)

## ✨ Features

- **📁 File Transfer** — Drag-and-drop on desktop, file picker on mobile. Progress bars, speed indicators, resume on disconnect. Up to 2GB per file.
- **💬 Chat** — Real-time messaging between connected devices.
- **📋 Clipboard Sharing** — Paste on one device, appears on the other.
- **🔍 Auto-Discovery** — Desktop broadcasts on LAN; mobile finds it automatically. Manual IP fallback.
- **📱 Device Info** — See connected device name, OS, IP, battery, and storage.

## 🏗️ Architecture

```
┌──────────────────┐         WiFi          ┌──────────────────┐
│   Desktop (PC)   │◄─────────────────────►│  Mobile (Phone)  │
│                  │     WebSocket (LAN)    │                  │
│  Electron App    │                        │  Capacitor App   │
│  WS Server :8765 │                        │  WS Client       │
│  UDP Broadcast   │                        │  Auto-discover   │
└──────────────────┘                        └──────────────────┘
```

**Desktop (Windows):** Electron app hosting a WebSocket server  
**Mobile (Android):** Capacitor-wrapped web app as WebSocket client  
**Shared:** React 18 + TypeScript + Tailwind CSS

## 📸 Screenshots

| Desktop | Mobile |
|---------|--------|
| ![Desktop](docs/screenshots/desktop-placeholder.png) | ![Mobile](docs/screenshots/mobile-placeholder.png) |

## 🚀 Quick Start

### Prerequisites

- Node.js 18+
- npm 9+
- Android Studio (for mobile build)

### Development

```bash
# Install dependencies
npm install

# Run web UI (both platforms share this)
npm run dev

# Run Electron desktop app (dev mode)
npm run electron:dev

# Build for Android
npm run cap:sync
npm run cap:android
```

### Production Build

```bash
# Build Electron Windows installer
npm run electron:build

# Build Android APK
npm run build
npx cap sync android
cd android && ./gradlew assembleDebug
```

## 🔧 Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| Port | 8765 | WebSocket server port |
| Device Name | Auto-detected | Shown to connected devices |
| Download Dir | System Downloads | Where received files are saved |

## 📡 Protocol

All communication uses JSON over WebSocket:

| Message Type | Direction | Description |
|-------------|-----------|-------------|
| `discover` / `discover-ack` | Both | Device handshake |
| `chat` | Both | Text messages |
| `clipboard` | Both | Clipboard sync |
| `file-offer` | Sender → Receiver | Propose file transfer |
| `file-accept` | Receiver → Sender | Accept (with optional resume offset) |
| `file-chunk` | Sender → Receiver | 1MB base64 chunk |
| `file-progress` | Receiver → Sender | Acknowledge received bytes |
| `file-complete` | Both | Transfer finished |
| `file-error` | Both | Transfer failed |

## 📂 Project Structure

```
lanlink/
├── src/                    # Shared React UI
│   ├── components/         # UI components (Sidebar, FilesTab, ChatTab, SettingsTab)
│   ├── hooks/              # App state context and hooks
│   ├── lib/                # Protocol, WS client, file utilities
│   ├── types/              # TypeScript type definitions
│   ├── App.tsx             # Root component
│   └── main.tsx            # Entry point
├── electron/               # Electron main process
│   ├── main.ts             # Window + IPC + server bootstrap
│   ├── preload.ts          # Secure bridge to renderer
│   ├── ws-server.ts        # WebSocket server
│   └── discovery.ts        # UDP LAN broadcast
├── .github/workflows/      # CI/CD (Electron EXE + Android APK)
├── capacitor.config.ts     # Capacitor (Android) config
├── electron-builder.yml    # Electron packaging config
└── package.json
```

## 🛡️ Security

- All communication is local (LAN only) — no data leaves your network
- Electron uses `contextIsolation` and `preload` scripts (no `nodeIntegration`)
- No persistent storage of messages or files

## 🤝 Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/awesome`)
3. Commit your changes (`git commit -m 'Add awesome feature'`)
4. Push to the branch (`git push origin feature/awesome`)
5. Open a Pull Request

## 📄 License

MIT © [Tapiwa Makandigona](https://github.com/TapiwaMakanworka)

---

**Built with ❤️ for seamless local device communication.**
