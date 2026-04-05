/**
 * [INTENT] Shared TypeScript types for the LanLink app
 * [CONSTRAINT] Keep types pure — no runtime logic here
 */

export interface Device {
  name: string;
  os: string;
  ip: string;
  battery?: number;
  storageAvailable?: number;
  connected: boolean;
}

export interface ChatEntry {
  id: string;
  content: string;
  timestamp: number;
  sender: 'local' | 'remote';
}

export type TabId = 'files' | 'chat' | 'settings';

export interface AppSettings {
  deviceName: string;
  port: number;
  downloadDir: string;
}
