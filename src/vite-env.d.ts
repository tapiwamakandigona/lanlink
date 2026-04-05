/// <reference types="vite/client" />

/**
 * [INTENT] TypeScript declarations for Vite environment and Electron preload API
 */

interface ElectronAPI {
  getServerInfo: () => Promise<{ ip: string; port: number }>;
  selectFiles: () => Promise<string[]>;
  saveFile: (name: string, data: ArrayBuffer) => Promise<string>;
  getDownloadsPath: () => Promise<string>;
  onServerStarted: (callback: (info: { ip: string; port: number }) => void) => void;
}

interface Window {
  electronAPI?: ElectronAPI;
  Capacitor?: unknown;
}
