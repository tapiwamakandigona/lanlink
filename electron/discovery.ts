/**
 * [INTENT] LAN discovery via UDP broadcast so mobile can find desktop
 * [CONSTRAINT] Broadcasts every 3 seconds on the discovery port
 * [EDGE-CASE] Firewall may block UDP; mobile falls back to manual IP entry
 */

import dgram from 'dgram';

const DISCOVERY_PORT = 8766;
const BROADCAST_INTERVAL = 3000;

let broadcastSocket: dgram.Socket | null = null;
let broadcastTimer: ReturnType<typeof setInterval> | null = null;

/**
 * [INTENT] Start broadcasting presence on the LAN
 */
export function startDiscovery(ip: string, wsPort: number): void {
  broadcastSocket = dgram.createSocket({ type: 'udp4', reuseAddr: true });

  broadcastSocket.bind(() => {
    broadcastSocket!.setBroadcast(true);

    const message = JSON.stringify({
      type: 'lanlink-discovery',
      ip,
      port: wsPort,
      deviceName: require('os').hostname(),
    });

    const broadcastAddress = getBroadcastAddress(ip);
    const buffer = Buffer.from(message);

    broadcastTimer = setInterval(() => {
      try {
        broadcastSocket!.send(buffer, 0, buffer.length, DISCOVERY_PORT, broadcastAddress);
      } catch (err) {
        console.error('[Discovery] Broadcast failed:', err);
      }
    }, BROADCAST_INTERVAL);

    // Also send immediately
    broadcastSocket!.send(buffer, 0, buffer.length, DISCOVERY_PORT, broadcastAddress);
    console.log(`[Discovery] Broadcasting on ${broadcastAddress}:${DISCOVERY_PORT}`);
  });

  broadcastSocket.on('error', (err) => {
    console.error('[Discovery] Socket error:', err);
  });
}

export function stopDiscovery(): void {
  if (broadcastTimer) {
    clearInterval(broadcastTimer);
    broadcastTimer = null;
  }
  if (broadcastSocket) {
    broadcastSocket.close();
    broadcastSocket = null;
  }
}

/**
 * [INTENT] Calculate broadcast address from IP (assumes /24 subnet)
 * [EDGE-CASE] Non-/24 subnets will need manual IP entry
 */
function getBroadcastAddress(ip: string): string {
  const parts = ip.split('.');
  parts[3] = '255';
  return parts.join('.');
}
