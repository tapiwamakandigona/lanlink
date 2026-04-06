/**
 * [INTENT] HTTP static file server for LanLink web mode
 * [CONSTRAINT] Serves built dist/ files so any LAN device can open a browser
 * [EDGE-CASE] Must handle CORS for WebSocket cross-origin; port conflicts
 */

import http from 'http';
import fs from 'fs';
import path from 'path';

const MIME_TYPES: Record<string, string> = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.map': 'application/json',
};

let server: http.Server | null = null;

/**
 * [INTENT] Start an HTTP server to serve the built web assets
 * [CONSTRAINT] Serves from the dist/ folder adjacent to dist-electron/
 * [EDGE-CASE] Falls back to index.html for SPA client-side routing
 */
export function startWebServer(
  distDir: string,
  port: number,
  wsPort: number,
): Promise<void> {
  return new Promise((resolve, reject) => {
    server = http.createServer((req, res) => {
      // CORS headers for web clients
      res.setHeader('Access-Control-Allow-Origin', '*');
      res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
      res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

      if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
      }

      // Serve a special endpoint for auto-config (tells web client the WS port)
      if (req.url === '/__lanlink_config__') {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ wsPort }));
        return;
      }

      const urlPath = req.url?.split('?')[0] ?? '/';
      let filePath = path.join(distDir, urlPath === '/' ? 'index.html' : urlPath);

      // Security: prevent path traversal
      if (!filePath.startsWith(distDir)) {
        res.writeHead(403);
        res.end('Forbidden');
        return;
      }

      fs.stat(filePath, (err, stats) => {
        if (err || !stats.isFile()) {
          // SPA fallback: serve index.html for any non-file route
          filePath = path.join(distDir, 'index.html');
          fs.stat(filePath, (err2) => {
            if (err2) {
              res.writeHead(404);
              res.end('Not Found');
              return;
            }
            serveFile(filePath, res);
          });
          return;
        }
        serveFile(filePath, res);
      });
    });

    server.on('error', (err: NodeJS.ErrnoException) => {
      if (err.code === 'EADDRINUSE') {
        console.error(`[WebServer] Port ${port} already in use`);
      }
      reject(err);
    });

    server.listen(port, '0.0.0.0', () => {
      console.log(`[WebServer] Serving on port ${port}`);
      resolve();
    });
  });
}

function serveFile(filePath: string, res: http.ServerResponse): void {
  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  const stream = fs.createReadStream(filePath);
  res.writeHead(200, { 'Content-Type': contentType });
  stream.pipe(res);
  stream.on('error', () => {
    res.writeHead(500);
    res.end('Internal Server Error');
  });
}

export function stopWebServer(): void {
  if (server) {
    server.close();
    server = null;
  }
}
