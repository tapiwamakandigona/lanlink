/**
 * [INTENT] Electron preload script — securely expose APIs to the renderer
 * [CONSTRAINT] Must use contextBridge; no direct Node.js access in renderer
 */

import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('electronAPI', {
  getServerInfo: () => ipcRenderer.invoke('get-server-info'),
  selectFiles: () => ipcRenderer.invoke('select-files'),
  saveFile: (name: string, data: ArrayBuffer) =>
    ipcRenderer.invoke('save-file', name, Buffer.from(data)),
  getDownloadsPath: () => ipcRenderer.invoke('get-downloads-path'),
  onServerStarted: (callback: (info: { ip: string; port: number; webUrl: string; webPort: number }) => void) => {
    ipcRenderer.on('server-started', (_event, info) => callback(info));
  },
});
