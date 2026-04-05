/**
 * [INTENT] Shared WebSocket message protocol types for LanLink
 * [CONSTRAINT] All messages must have a `type` discriminator for safe parsing
 * [EDGE-CASE] file-chunk data is base64 encoded; large messages need chunking
 */

// --- Discovery ---
export interface DiscoverMessage {
  type: 'discover';
  deviceName: string;
  os: string;
}

export interface DiscoverAckMessage {
  type: 'discover-ack';
  deviceName: string;
  os: string;
  ip: string;
}

// --- Chat ---
export interface ChatMessage {
  type: 'chat';
  content: string;
  timestamp: number;
  sender: string;
}

export interface ClipboardMessage {
  type: 'clipboard';
  content: string;
}

// --- File Transfer ---
export interface FileOfferMessage {
  type: 'file-offer';
  id: string;
  name: string;
  size: number;
  mime: string;
}

export interface FileAcceptMessage {
  type: 'file-accept';
  id: string;
  offset?: number; // [EDGE-CASE] Resume from offset on reconnect
}

export interface FileChunkMessage {
  type: 'file-chunk';
  id: string;
  offset: number;
  data: string; // base64
}

export interface FileProgressMessage {
  type: 'file-progress';
  id: string;
  received: number;
}

export interface FileCompleteMessage {
  type: 'file-complete';
  id: string;
}

export interface FileErrorMessage {
  type: 'file-error';
  id: string;
  error: string;
}

// --- Device Info ---
export interface DeviceInfoMessage {
  type: 'device-info';
  deviceName: string;
  os: string;
  ip: string;
  battery?: number;
  storageAvailable?: number;
}

export interface PingMessage {
  type: 'ping';
}

export interface PongMessage {
  type: 'pong';
}

// --- Union type ---
export type WSMessage =
  | DiscoverMessage
  | DiscoverAckMessage
  | ChatMessage
  | ClipboardMessage
  | FileOfferMessage
  | FileAcceptMessage
  | FileChunkMessage
  | FileProgressMessage
  | FileCompleteMessage
  | FileErrorMessage
  | DeviceInfoMessage
  | PingMessage
  | PongMessage;

/**
 * [INTENT] Safely parse an incoming WebSocket message
 * [CONSTRAINT] Returns null on invalid JSON rather than throwing
 */
export function parseMessage(data: string): WSMessage | null {
  try {
    const msg = JSON.parse(data);
    if (msg && typeof msg.type === 'string') {
      return msg as WSMessage;
    }
    return null;
  } catch {
    return null;
  }
}

export function serializeMessage(msg: WSMessage): string {
  return JSON.stringify(msg);
}

export const CHUNK_SIZE = 1024 * 1024; // 1MB chunks
export const DEFAULT_PORT = 8765;
export const DISCOVERY_PORT = 8766;
