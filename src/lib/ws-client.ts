/**
 * [INTENT] WebSocket client for connecting to LanLink desktop server
 * [CONSTRAINT] Must auto-reconnect on disconnect; handle both browser and Capacitor
 * [EDGE-CASE] Network changes on mobile can drop connections silently
 */

import {
  WSMessage,
  parseMessage,
  serializeMessage,
  DEFAULT_PORT,
} from './protocol';

export type ConnectionState = 'disconnected' | 'connecting' | 'connected';
export type MessageHandler = (msg: WSMessage) => void;
export type StateHandler = (state: ConnectionState) => void;

interface WSClientOptions {
  onMessage: MessageHandler;
  onStateChange: StateHandler;
  reconnectInterval?: number;
  maxReconnectAttempts?: number;
}

/**
 * [INTENT] Manages a WebSocket connection to the desktop server
 * [CONSTRAINT] Singleton-style — one active connection at a time
 */
export class WSClient {
  private ws: WebSocket | null = null;
  private url = '';
  private options: WSClientOptions;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectAttempts = 0;
  private _state: ConnectionState = 'disconnected';
  private intentionalClose = false;

  constructor(options: WSClientOptions) {
    this.options = options;
  }

  get state(): ConnectionState {
    return this._state;
  }

  private setState(state: ConnectionState): void {
    this._state = state;
    this.options.onStateChange(state);
  }

  /**
   * [INTENT] Connect to a LanLink server at the given IP
   * [EDGE-CASE] If already connected, disconnect first
   */
  connect(ip: string, port: number = DEFAULT_PORT): void {
    this.disconnect();
    this.intentionalClose = false;
    this.url = `ws://${ip}:${port}`;
    this.setState('connecting');
    this.createConnection();
  }

  private createConnection(): void {
    try {
      this.ws = new WebSocket(this.url);

      this.ws.onopen = () => {
        this.reconnectAttempts = 0;
        this.setState('connected');
      };

      this.ws.onmessage = (event) => {
        const msg = parseMessage(event.data as string);
        if (msg) {
          this.options.onMessage(msg);
        }
      };

      this.ws.onclose = () => {
        this.ws = null;
        if (!this.intentionalClose) {
          this.setState('disconnected');
          this.scheduleReconnect();
        } else {
          this.setState('disconnected');
        }
      };

      this.ws.onerror = () => {
        // onclose will fire after onerror
      };
    } catch {
      this.setState('disconnected');
      this.scheduleReconnect();
    }
  }

  private scheduleReconnect(): void {
    const maxAttempts = this.options.maxReconnectAttempts ?? 20;
    if (this.reconnectAttempts >= maxAttempts) return;

    const interval = this.options.reconnectInterval ?? 3000;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectAttempts++;
      this.setState('connecting');
      this.createConnection();
    }, interval);
  }

  /**
   * [INTENT] Send a message to the connected server
   * [CONSTRAINT] Silently drops if not connected (caller should check state)
   */
  send(msg: WSMessage): boolean {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(serializeMessage(msg));
      return true;
    }
    return false;
  }

  disconnect(): void {
    this.intentionalClose = true;
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    this.setState('disconnected');
  }
}

/**
 * [INTENT] Detect if running inside Electron
 */
export function isElectron(): boolean {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return typeof window !== 'undefined' && !!(window as any).electronAPI;
}

/**
 * [INTENT] Detect if running inside Capacitor
 */
export function isCapacitor(): boolean {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return typeof window !== 'undefined' && !!(window as any).Capacitor;
}
