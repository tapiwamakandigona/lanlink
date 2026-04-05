/**
 * [INTENT] WebSocket server for the desktop Electron app
 * [CONSTRAINT] Runs in Electron main process (Node.js); handles multiple clients
 * [EDGE-CASE] Must relay messages between connected clients; handle abrupt disconnects
 */

import { WebSocketServer, WebSocket } from 'ws';
import { networkInterfaces } from 'os';
import { hostname } from 'os';

let wss: WebSocketServer | null = null;

/**
 * [INTENT] Get local LAN IP for the discover-ack response
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

export function createWSServer(port: number): WebSocketServer {
  wss = new WebSocketServer({ port });

  wss.on('connection', (ws: WebSocket) => {
    console.log('[WS] Client connected');

    // Send discover-ack immediately
    const ack = JSON.stringify({
      type: 'discover-ack',
      deviceName: hostname(),
      os: `Windows ${process.arch}`,
      ip: getLocalIP(),
    });
    ws.send(ack);

    ws.on('message', (raw: Buffer) => {
      try {
        const data = raw.toString();
        const msg = JSON.parse(data);

        // [INTENT] Relay messages to all OTHER connected clients
        if (wss) {
          for (const client of wss.clients) {
            if (client !== ws && client.readyState === WebSocket.OPEN) {
              client.send(data);
            }
          }
        }

        // Handle ping
        if (msg.type === 'ping') {
          ws.send(JSON.stringify({ type: 'pong' }));
        }
      } catch (err) {
        console.error('[WS] Failed to process message:', err);
      }
    });

    ws.on('close', () => {
      console.log('[WS] Client disconnected');
    });

    ws.on('error', (err) => {
      console.error('[WS] Client error:', err);
    });
  });

  wss.on('error', (err) => {
    console.error('[WS] Server error:', err);
  });

  return wss;
}

export function stopWSServer(): void {
  if (wss) {
    wss.close();
    wss = null;
  }
}
