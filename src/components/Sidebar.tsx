/**
 * [INTENT] Sidebar showing connected device info and connection controls
 * [CONSTRAINT] Must work on both desktop (always visible) and mobile (collapsible)
 * [EDGE-CASE] Web mode auto-connects — hide manual IP input; show web URL in Electron
 */

import { useState, useEffect } from 'react';
import { useApp } from '@/hooks/useAppContext';
import { isElectron, isWebMode } from '@/lib/ws-client';
import { Wifi, WifiOff, Loader2, Monitor, Smartphone, Battery, HardDrive, Globe, Copy, Check } from 'lucide-react';
import { formatBytes } from '@/lib/file-utils';
import { DEFAULT_PORT } from '@/lib/protocol';

export function Sidebar() {
  const { state, connect, disconnect } = useApp();
  const [ipInput, setIpInput] = useState('');
  const [webUrl, setWebUrl] = useState('');
  const [copied, setCopied] = useState(false);

  const handleConnect = () => {
    const ip = ipInput.trim();
    if (ip) connect(ip);
  };

  // [INTENT] Get the web access URL from Electron main process
  useEffect(() => {
    if (isElectron()) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const api = (window as any).electronAPI;
      api.getServerInfo().then((info: { webUrl?: string }) => {
        if (info.webUrl) setWebUrl(info.webUrl);
      });
      api.onServerStarted((info: { webUrl?: string }) => {
        if (info.webUrl) setWebUrl(info.webUrl);
      });
    }
  }, []);

  const handleCopyUrl = async () => {
    try {
      await navigator.clipboard.writeText(webUrl);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch { /* ignore */ }
  };

  const statusColor = {
    disconnected: 'text-red-400',
    connecting: 'text-yellow-400',
    connected: 'text-green-400',
  }[state.connection];

  const StatusIcon = {
    disconnected: WifiOff,
    connecting: Loader2,
    connected: Wifi,
  }[state.connection];

  const webMode = isWebMode();

  return (
    <div className="w-full lg:w-72 bg-gray-900 border-b lg:border-b-0 lg:border-r border-gray-800 p-4 flex flex-col gap-4">
      {/* Logo */}
      <div className="flex items-center gap-2">
        <div className="w-8 h-8 rounded-lg bg-primary-600 flex items-center justify-center text-white font-bold text-sm">
          LL
        </div>
        <h1 className="text-lg font-bold text-white">LanLink</h1>
        {webMode && (
          <span className="ml-auto text-[10px] bg-primary-600/20 text-primary-400 px-2 py-0.5 rounded-full font-medium">
            WEB
          </span>
        )}
      </div>

      {/* Connection Status */}
      <div className={`flex items-center gap-2 text-sm ${statusColor}`}>
        <StatusIcon className={`w-4 h-4 ${state.connection === 'connecting' ? 'animate-spin' : ''}`} />
        <span className="capitalize">{state.connection}</span>
        {webMode && state.connection === 'connecting' && (
          <span className="text-xs text-gray-500">Auto-connecting...</span>
        )}
      </div>

      {/* Connect Form — only show for non-web-mode disconnected */}
      {state.connection === 'disconnected' && !webMode && (
        <div className="flex flex-col gap-2">
          <input
            type="text"
            placeholder={`Server IP (port ${DEFAULT_PORT})`}
            value={ipInput}
            onChange={(e) => setIpInput(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleConnect()}
            className="bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-primary-500"
          />
          <button
            onClick={handleConnect}
            disabled={!ipInput.trim()}
            className="bg-primary-600 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed text-white text-sm font-medium py-2 rounded-lg transition-colors"
          >
            Connect
          </button>
        </div>
      )}

      {state.connection === 'connected' && !webMode && (
        <button
          onClick={disconnect}
          className="bg-red-600/20 hover:bg-red-600/30 text-red-400 text-sm font-medium py-2 rounded-lg transition-colors border border-red-600/30"
        >
          Disconnect
        </button>
      )}

      {/* Remote Device Info */}
      {state.remoteDevice && (
        <div className="bg-gray-800/50 rounded-lg p-3 space-y-2">
          <div className="flex items-center gap-2 text-white text-sm font-medium">
            {state.remoteDevice.os.toLowerCase().includes('android') ? (
              <Smartphone className="w-4 h-4 text-primary-400" />
            ) : (
              <Monitor className="w-4 h-4 text-primary-400" />
            )}
            {state.remoteDevice.name}
          </div>
          <div className="text-xs text-gray-400 space-y-1">
            <div>IP: {state.remoteDevice.ip}</div>
            <div>OS: {state.remoteDevice.os}</div>
            {state.remoteDevice.battery !== undefined && (
              <div className="flex items-center gap-1">
                <Battery className="w-3 h-3" />
                {state.remoteDevice.battery}%
              </div>
            )}
            {state.remoteDevice.storageAvailable !== undefined && (
              <div className="flex items-center gap-1">
                <HardDrive className="w-3 h-3" />
                {formatBytes(state.remoteDevice.storageAvailable)} free
              </div>
            )}
          </div>
        </div>
      )}

      {/* Web Access URL — show only in Electron when web server is running */}
      {!webMode && webUrl && (
        <div className="bg-primary-600/10 border border-primary-500/20 rounded-lg p-3 space-y-2">
          <div className="flex items-center gap-2 text-primary-400 text-xs font-medium">
            <Globe className="w-3.5 h-3.5" />
            Web Access
          </div>
          <div className="flex items-center gap-2">
            <code className="text-xs text-white bg-gray-800 px-2 py-1 rounded flex-1 truncate">
              {webUrl}
            </code>
            <button
              onClick={handleCopyUrl}
              className="p-1 text-gray-400 hover:text-primary-400 transition-colors"
              title="Copy URL"
            >
              {copied ? <Check className="w-3.5 h-3.5 text-green-400" /> : <Copy className="w-3.5 h-3.5" />}
            </button>
          </div>
          <p className="text-[10px] text-gray-500">
            Open this URL on any device on your WiFi
          </p>
        </div>
      )}

      {/* Server mode hint */}
      <div className="mt-auto text-xs text-gray-600">
        {webMode
          ? 'Connected via browser — files transfer over your local WiFi'
          : state.serverIp
            ? `Server: ${state.serverIp}`
            : 'Enter desktop IP to connect'}
      </div>
    </div>
  );
}
