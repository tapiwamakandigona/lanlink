/**
 * [INTENT] Sidebar showing connected device info and connection controls
 * [CONSTRAINT] Must work on both desktop (always visible) and mobile (collapsible)
 */

import { useState } from 'react';
import { useApp } from '@/hooks/useAppContext';
import { Wifi, WifiOff, Loader2, Monitor, Smartphone, Battery, HardDrive } from 'lucide-react';
import { formatBytes } from '@/lib/file-utils';
import { DEFAULT_PORT } from '@/lib/protocol';

export function Sidebar() {
  const { state, connect, disconnect } = useApp();
  const [ipInput, setIpInput] = useState('');

  const handleConnect = () => {
    const ip = ipInput.trim();
    if (ip) connect(ip);
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

  return (
    <div className="w-full lg:w-72 bg-gray-900 border-b lg:border-b-0 lg:border-r border-gray-800 p-4 flex flex-col gap-4">
      {/* Logo */}
      <div className="flex items-center gap-2">
        <div className="w-8 h-8 rounded-lg bg-primary-600 flex items-center justify-center text-white font-bold text-sm">
          LL
        </div>
        <h1 className="text-lg font-bold text-white">LanLink</h1>
      </div>

      {/* Connection Status */}
      <div className={`flex items-center gap-2 text-sm ${statusColor}`}>
        <StatusIcon className={`w-4 h-4 ${state.connection === 'connecting' ? 'animate-spin' : ''}`} />
        <span className="capitalize">{state.connection}</span>
      </div>

      {/* Connect Form */}
      {state.connection === 'disconnected' && (
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

      {state.connection === 'connected' && (
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

      {/* Server mode hint for Electron */}
      <div className="mt-auto text-xs text-gray-600">
        {state.serverIp ? `Server: ${state.serverIp}` : 'Enter desktop IP to connect'}
      </div>
    </div>
  );
}
