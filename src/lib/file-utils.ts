/**
 * [INTENT] File chunking utilities for large file transfers
 * [CONSTRAINT] Chunks are 1MB base64-encoded; must handle files up to 2GB
 * [EDGE-CASE] Browser File API vs Node.js Buffer — platform detection needed
 */

import { CHUNK_SIZE } from './protocol';

export interface FileTransfer {
  id: string;
  name: string;
  size: number;
  mime: string;
  progress: number; // bytes transferred
  speed: number; // bytes per second
  status: 'pending' | 'transferring' | 'complete' | 'error' | 'paused';
  direction: 'send' | 'receive';
  startTime: number;
  chunks: string[]; // received base64 chunks indexed by offset/CHUNK_SIZE
  error?: string;
}

/**
 * [INTENT] Read a file chunk as base64 from a browser File object
 * [CONSTRAINT] Must use FileReader API for browser compatibility
 */
export async function readFileChunk(
  file: File,
  offset: number
): Promise<string> {
  const slice = file.slice(offset, offset + CHUNK_SIZE);
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      if (reader.result instanceof ArrayBuffer) {
        const bytes = new Uint8Array(reader.result);
        resolve(uint8ToBase64(bytes));
      } else {
        reject(new Error('Unexpected FileReader result type'));
      }
    };
    reader.onerror = () => reject(reader.error);
    reader.readAsArrayBuffer(slice);
  });
}

/**
 * [INTENT] Convert Uint8Array to base64 string
 * [EDGE-CASE] Large arrays may exceed call stack with String.fromCharCode spread
 */
export function uint8ToBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunkSize = 8192;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize);
    for (let j = 0; j < chunk.length; j++) {
      binary += String.fromCharCode(chunk[j]);
    }
  }
  return btoa(binary);
}

/**
 * [INTENT] Convert base64 string back to Uint8Array
 */
export function base64ToUint8(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/**
 * [INTENT] Assemble received chunks into a downloadable Blob
 * [CONSTRAINT] Chunks array must be complete (no gaps)
 */
export function assembleFile(
  chunks: string[],
  mime: string
): Blob {
  const parts = chunks.map((chunk) => base64ToUint8(chunk).buffer as ArrayBuffer);
  return new Blob(parts, { type: mime });
}

/**
 * [INTENT] Calculate transfer speed in bytes/second
 */
export function calculateSpeed(
  bytesTransferred: number,
  startTime: number
): number {
  const elapsed = (Date.now() - startTime) / 1000;
  if (elapsed <= 0) return 0;
  return Math.round(bytesTransferred / elapsed);
}

/**
 * [INTENT] Format bytes into human-readable string
 */
export function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
}

/**
 * [INTENT] Format speed into human-readable string
 */
export function formatSpeed(bytesPerSecond: number): string {
  return `${formatBytes(bytesPerSecond)}/s`;
}

/**
 * [INTENT] Generate a unique file transfer ID
 */
export function generateTransferId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

/**
 * [INTENT] Get MIME type from filename extension
 * [EDGE-CASE] Unknown extensions default to application/octet-stream
 */
export function getMimeType(filename: string): string {
  const ext = filename.split('.').pop()?.toLowerCase() ?? '';
  const mimeMap: Record<string, string> = {
    jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png',
    gif: 'image/gif', webp: 'image/webp', svg: 'image/svg+xml',
    mp4: 'video/mp4', webm: 'video/webm', mp3: 'audio/mpeg',
    wav: 'audio/wav', pdf: 'application/pdf', zip: 'application/zip',
    txt: 'text/plain', json: 'application/json', html: 'text/html',
    css: 'text/css', js: 'application/javascript',
    doc: 'application/msword', docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    xls: 'application/vnd.ms-excel', xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    apk: 'application/vnd.android.package-archive',
  };
  return mimeMap[ext] ?? 'application/octet-stream';
}
