/**
 * [INTENT] Electron main process — creates window, starts WebSocket server, handles file I/O
 * [CONSTRAINT] WebSocket server runs in main process (Node.js); renderer is the React UI
 * [EDGE-CASE] Must handle port conflicts, firewall prompts on Windows
 */

import { app, BrowserWindow, ipcMain, dialog } from 'electron';
import path from 'path';
import { createWSServer, stopWSServer } from './ws-server';
import { startDiscovery, stopDiscovery } from './discovery';
import { networkInterfaces } from 'os';
import fs from 'fs';

const DEFAULT_PORT = 8765;

let mainWindow: BrowserWindow | null = null;

/**
 * [INTENT] Get the local LAN IP address (not loopback)
 * [EDGE-CASE] Multiple network interfaces — pick the first non-internal IPv4
 */
function getLocalIP(): string {
  const nets = networkInterfaces();
  for (const name of Object.keys(nets)) {
    for (const net of nets[name] ?? []) {
      if (net.family === 'IPv4' && !net.internal) {
        return net.address;
      }
    }
  }
  return '127.0.0.1';
}

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 750,
    minWidth: 800,
    minHeight: 600,
    title: 'LanLink',
    backgroundColor: '#030712',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  // [INTENT] Load Vite dev server in dev, built files in production
  if (process.env.VITE_DEV_SERVER_URL) {
    mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL);
    mainWindow.webContents.openDevTools();
  } else {
    mainWindow.loadFile(path.join(__dirname, '../dist/index.html'));
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(async () => {
  createWindow();

  const localIP = getLocalIP();
  const port = DEFAULT_PORT;

  // Start WebSocket server
  try {
    createWSServer(port);
    console.log(`[LanLink] WebSocket server started on ${localIP}:${port}`);
  } catch (err) {
    console.error('[LanLink] Failed to start WebSocket server:', err);
  }

  // Start LAN discovery broadcast
  try {
    startDiscovery(localIP, port);
  } catch (err) {
    console.error('[LanLink] Failed to start discovery:', err);
  }

  // Notify renderer of server info
  mainWindow?.webContents.on('did-finish-load', () => {
    mainWindow?.webContents.send('server-started', { ip: localIP, port });
  });

  // IPC handlers
  ipcMain.handle('get-server-info', () => ({ ip: localIP, port }));

  ipcMain.handle('select-files', async () => {
    const result = await dialog.showOpenDialog(mainWindow!, {
      properties: ['openFile', 'multiSelections'],
    });
    return result.filePaths;
  });

  ipcMain.handle('save-file', async (_event, name: string, data: Buffer) => {
    const downloadsPath = app.getPath('downloads');
    const filePath = path.join(downloadsPath, name);
    await fs.promises.writeFile(filePath, data);
    return filePath;
  });

  ipcMain.handle('get-downloads-path', () => app.getPath('downloads'));
});

app.on('window-all-closed', () => {
  stopWSServer();
  stopDiscovery();
  app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});
