/**
 * [INTENT] Global app state using React Context — manages connection, transfers, chat
 * [CONSTRAINT] Single source of truth; all WS communication flows through here
 * [EDGE-CASE] Must handle reconnection state without losing in-progress transfers
 */

import React, { createContext, useContext, useReducer, useCallback, useRef, useEffect } from 'react';
import { WSClient, ConnectionState } from '@/lib/ws-client';
import { WSMessage, CHUNK_SIZE, DEFAULT_PORT } from '@/lib/protocol';
import {
  FileTransfer,
  readFileChunk,
  assembleFile,
  calculateSpeed,
  generateTransferId,
  getMimeType,
} from '@/lib/file-utils';
import { Device, ChatEntry, AppSettings } from '@/types';

// --- State ---
interface AppState {
  connection: ConnectionState;
  remoteDevice: Device | null;
  chat: ChatEntry[];
  transfers: FileTransfer[];
  settings: AppSettings;
  serverIp: string;
}

const defaultSettings: AppSettings = {
  deviceName: navigator.userAgent.includes('Android') ? 'Android Phone' : 'Desktop PC',
  port: DEFAULT_PORT,
  downloadDir: 'Downloads',
};

const initialState: AppState = {
  connection: 'disconnected',
  remoteDevice: null,
  chat: [],
  transfers: [],
  settings: defaultSettings,
  serverIp: '',
};

// --- Actions ---
type Action =
  | { type: 'SET_CONNECTION'; state: ConnectionState }
  | { type: 'SET_REMOTE_DEVICE'; device: Device | null }
  | { type: 'ADD_CHAT'; entry: ChatEntry }
  | { type: 'ADD_TRANSFER'; transfer: FileTransfer }
  | { type: 'UPDATE_TRANSFER'; id: string; updates: Partial<FileTransfer> }
  | { type: 'UPDATE_TRANSFER_CHUNK'; id: string; chunkIndex: number; data: string; progress: number }
  | { type: 'UPDATE_SETTINGS'; settings: Partial<AppSettings> }
  | { type: 'SET_SERVER_IP'; ip: string };

function reducer(state: AppState, action: Action): AppState {
  switch (action.type) {
    case 'SET_CONNECTION':
      return {
        ...state,
        connection: action.state,
        remoteDevice: action.state === 'disconnected' ? null : state.remoteDevice,
      };
    case 'SET_REMOTE_DEVICE':
      return { ...state, remoteDevice: action.device };
    case 'ADD_CHAT':
      return { ...state, chat: [...state.chat, action.entry] };
    case 'ADD_TRANSFER':
      return { ...state, transfers: [...state.transfers, action.transfer] };
    case 'UPDATE_TRANSFER':
      return {
        ...state,
        transfers: state.transfers.map((t) =>
          t.id === action.id ? { ...t, ...action.updates } : t
        ),
      };
    case 'UPDATE_TRANSFER_CHUNK': {
      return {
        ...state,
        transfers: state.transfers.map((t) => {
          if (t.id !== action.id) return t;
          const chunks = [...t.chunks];
          chunks[action.chunkIndex] = action.data;
          return {
            ...t,
            chunks,
            progress: action.progress,
            speed: calculateSpeed(action.progress, t.startTime),
          };
        }),
      };
    }
    case 'UPDATE_SETTINGS':
      return { ...state, settings: { ...state.settings, ...action.settings } };
    case 'SET_SERVER_IP':
      return { ...state, serverIp: action.ip };
    default:
      return state;
  }
}

// --- Context ---
interface AppContextType {
  state: AppState;
  connect: (ip: string) => void;
  disconnect: () => void;
  sendChat: (content: string) => void;
  sendClipboard: (content: string) => void;
  sendFile: (file: File) => void;
  acceptFile: (id: string) => void;
  updateSettings: (settings: Partial<AppSettings>) => void;
}

const AppContext = createContext<AppContextType | null>(null);

export function useApp(): AppContextType {
  const ctx = useContext(AppContext);
  if (!ctx) throw new Error('useApp must be used within AppProvider');
  return ctx;
}

/**
 * [INTENT] Root state provider — wraps the app with WS connection + state management
 */
export function AppProvider({ children }: { children: React.ReactNode }) {
  const [state, dispatch] = useReducer(reducer, initialState);
  const clientRef = useRef<WSClient | null>(null);
  const filesRef = useRef<Map<string, File>>(new Map()); // outgoing files by transfer ID
  const stateRef = useRef(state);
  stateRef.current = state;

  // [INTENT] Handle incoming WS messages and dispatch state updates
  const handleMessage = useCallback((msg: WSMessage) => {
    switch (msg.type) {
      case 'discover-ack':
        dispatch({
          type: 'SET_REMOTE_DEVICE',
          device: { name: msg.deviceName, os: msg.os, ip: msg.ip, connected: true },
        });
        // Send our info back
        clientRef.current?.send({
          type: 'device-info',
          deviceName: stateRef.current.settings.deviceName,
          os: navigator.userAgent.includes('Android') ? 'Android' : navigator.platform,
          ip: '',
        });
        break;

      case 'device-info':
        dispatch({
          type: 'SET_REMOTE_DEVICE',
          device: {
            name: msg.deviceName,
            os: msg.os,
            ip: msg.ip,
            battery: msg.battery,
            storageAvailable: msg.storageAvailable,
            connected: true,
          },
        });
        break;

      case 'chat':
        dispatch({
          type: 'ADD_CHAT',
          entry: {
            id: `${msg.timestamp}-${Math.random()}`,
            content: msg.content,
            timestamp: msg.timestamp,
            sender: 'remote',
          },
        });
        break;

      case 'clipboard':
        // [INTENT] Auto-copy received clipboard content
        navigator.clipboard?.writeText(msg.content).catch(() => {
          // Clipboard API may not be available
        });
        dispatch({
          type: 'ADD_CHAT',
          entry: {
            id: `clip-${Date.now()}`,
            content: `📋 Clipboard: ${msg.content}`,
            timestamp: Date.now(),
            sender: 'remote',
          },
        });
        break;

      case 'file-offer':
        dispatch({
          type: 'ADD_TRANSFER',
          transfer: {
            id: msg.id,
            name: msg.name,
            size: msg.size,
            mime: msg.mime,
            progress: 0,
            speed: 0,
            status: 'pending',
            direction: 'receive',
            startTime: Date.now(),
            chunks: [],
          },
        });
        // Auto-accept for now
        clientRef.current?.send({ type: 'file-accept', id: msg.id });
        dispatch({ type: 'UPDATE_TRANSFER', id: msg.id, updates: { status: 'transferring', startTime: Date.now() } });
        break;

      case 'file-accept': {
        // [INTENT] Start sending file chunks when remote accepts
        const transfer = stateRef.current.transfers.find((t) => t.id === msg.id);
        const file = filesRef.current.get(msg.id);
        if (transfer && file) {
          const startOffset = msg.offset ?? 0;
          dispatch({
            type: 'UPDATE_TRANSFER',
            id: msg.id,
            updates: { status: 'transferring', startTime: Date.now() },
          });
          sendFileChunks(msg.id, file, startOffset);
        }
        break;
      }

      case 'file-chunk': {
        // [INTENT] Receive a chunk and track progress
        const chunkIndex = Math.floor(msg.offset / CHUNK_SIZE);
        const newProgress = msg.offset + atob(msg.data).length;
        dispatch({
          type: 'UPDATE_TRANSFER_CHUNK',
          id: msg.id,
          chunkIndex,
          data: msg.data,
          progress: newProgress,
        });
        // Send progress ack
        clientRef.current?.send({ type: 'file-progress', id: msg.id, received: newProgress });
        // Check if complete
        const t = stateRef.current.transfers.find((tr) => tr.id === msg.id);
        if (t && newProgress >= t.size) {
          dispatch({ type: 'UPDATE_TRANSFER', id: msg.id, updates: { status: 'complete' } });
          clientRef.current?.send({ type: 'file-complete', id: msg.id });
          // Download the file in browser
          const updatedTransfer = stateRef.current.transfers.find((tr) => tr.id === msg.id);
          if (updatedTransfer) {
            const allChunks = [...updatedTransfer.chunks];
            allChunks[chunkIndex] = msg.data;
            const blob = assembleFile(allChunks, updatedTransfer.mime);
            downloadBlob(blob, updatedTransfer.name);
          }
        }
        break;
      }

      case 'file-progress':
        dispatch({
          type: 'UPDATE_TRANSFER',
          id: msg.id,
          updates: { progress: msg.received },
        });
        break;

      case 'file-complete':
        dispatch({
          type: 'UPDATE_TRANSFER',
          id: msg.id,
          updates: { status: 'complete' },
        });
        filesRef.current.delete(msg.id);
        break;

      case 'file-error':
        dispatch({
          type: 'UPDATE_TRANSFER',
          id: msg.id,
          updates: { status: 'error', error: msg.error },
        });
        filesRef.current.delete(msg.id);
        break;

      case 'ping':
        clientRef.current?.send({ type: 'pong' });
        break;
    }
  }, []);

  /**
   * [INTENT] Send file in 1MB chunks with small delays to prevent flooding
   * [EDGE-CASE] Must stop if connection drops mid-transfer
   */
  const sendFileChunks = useCallback(
    async (id: string, file: File, startOffset: number) => {
      let offset = startOffset;
      while (offset < file.size) {
        const transfer = stateRef.current.transfers.find((t) => t.id === id);
        if (!transfer || transfer.status === 'error' || transfer.status === 'paused') break;
        if (stateRef.current.connection !== 'connected') break;

        try {
          const data = await readFileChunk(file, offset);
          const sent = clientRef.current?.send({
            type: 'file-chunk',
            id,
            offset,
            data,
          });
          if (!sent) break;
          offset += CHUNK_SIZE;
          dispatch({
            type: 'UPDATE_TRANSFER',
            id,
            updates: {
              progress: Math.min(offset, file.size),
              speed: calculateSpeed(Math.min(offset, file.size), transfer.startTime),
            },
          });
          // Small delay to prevent flooding
          await new Promise((r) => setTimeout(r, 10));
        } catch (err) {
          dispatch({
            type: 'UPDATE_TRANSFER',
            id,
            updates: { status: 'error', error: String(err) },
          });
          break;
        }
      }
    },
    []
  );

  // --- Public API ---
  const connect = useCallback(
    (ip: string) => {
      dispatch({ type: 'SET_SERVER_IP', ip });
      if (!clientRef.current) {
        clientRef.current = new WSClient({
          onMessage: handleMessage,
          onStateChange: (s) => dispatch({ type: 'SET_CONNECTION', state: s }),
        });
      }
      clientRef.current.connect(ip, stateRef.current.settings.port);
    },
    [handleMessage]
  );

  const disconnect = useCallback(() => {
    clientRef.current?.disconnect();
  }, []);

  const sendChat = useCallback((content: string) => {
    const entry: ChatEntry = {
      id: `${Date.now()}-${Math.random()}`,
      content,
      timestamp: Date.now(),
      sender: 'local',
    };
    dispatch({ type: 'ADD_CHAT', entry });
    clientRef.current?.send({
      type: 'chat',
      content,
      timestamp: entry.timestamp,
      sender: stateRef.current.settings.deviceName,
    });
  }, []);

  const sendClipboard = useCallback((content: string) => {
    clientRef.current?.send({ type: 'clipboard', content });
  }, []);

  const sendFile = useCallback((file: File) => {
    const id = generateTransferId();
    const transfer: FileTransfer = {
      id,
      name: file.name,
      size: file.size,
      mime: getMimeType(file.name),
      progress: 0,
      speed: 0,
      status: 'pending',
      direction: 'send',
      startTime: Date.now(),
      chunks: [],
    };
    filesRef.current.set(id, file);
    dispatch({ type: 'ADD_TRANSFER', transfer });
    clientRef.current?.send({
      type: 'file-offer',
      id,
      name: file.name,
      size: file.size,
      mime: transfer.mime,
    });
  }, []);

  const acceptFile = useCallback((id: string) => {
    clientRef.current?.send({ type: 'file-accept', id });
    dispatch({ type: 'UPDATE_TRANSFER', id, updates: { status: 'transferring', startTime: Date.now() } });
  }, []);

  const updateSettings = useCallback((settings: Partial<AppSettings>) => {
    dispatch({ type: 'UPDATE_SETTINGS', settings });
  }, []);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      clientRef.current?.disconnect();
    };
  }, []);

  return (
    <AppContext.Provider
      value={{
        state,
        connect,
        disconnect,
        sendChat,
        sendClipboard,
        sendFile,
        acceptFile,
        updateSettings,
      }}
    >
      {children}
    </AppContext.Provider>
  );
}

/**
 * [INTENT] Trigger a browser file download from a Blob
 * [EDGE-CASE] URL.revokeObjectURL to prevent memory leaks
 */
function downloadBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
