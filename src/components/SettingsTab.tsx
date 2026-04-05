/**
 * [INTENT] Settings tab — device name, port config, download directory
 * [CONSTRAINT] Settings are session-only; changes take effect on next connection
 */

import { useState } from 'react';
import { useApp } from '@/hooks/useAppContext';
import { Settings, Save } from 'lucide-react';

export function SettingsTab() {
  const { state, updateSettings } = useApp();
  const [name, setName] = useState(state.settings.deviceName);
  const [port, setPort] = useState(String(state.settings.port));
  const [saved, setSaved] = useState(false);

  const handleSave = () => {
    updateSettings({
      deviceName: name.trim() || 'LanLink Device',
      port: parseInt(port, 10) || 8765,
    });
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  return (
    <div className="p-4 max-w-md mx-auto space-y-6">
      <div className="flex items-center gap-2 text-white">
        <Settings className="w-5 h-5 text-primary-400" />
        <h2 className="text-lg font-semibold">Settings</h2>
      </div>

      <div className="space-y-4">
        <div>
          <label className="block text-sm text-gray-400 mb-1">Device Name</label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-primary-500"
          />
        </div>

        <div>
          <label className="block text-sm text-gray-400 mb-1">WebSocket Port</label>
          <input
            type="number"
            value={port}
            onChange={(e) => setPort(e.target.value)}
            min={1024}
            max={65535}
            className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white focus:outline-none focus:border-primary-500"
          />
          <p className="text-xs text-gray-600 mt-1">Changes apply on next connection</p>
        </div>

        <div>
          <label className="block text-sm text-gray-400 mb-1">Download Directory</label>
          <input
            type="text"
            value={state.settings.downloadDir}
            disabled
            className="w-full bg-gray-800/50 border border-gray-700 rounded-lg px-3 py-2 text-sm text-gray-500"
          />
          <p className="text-xs text-gray-600 mt-1">Files are saved via browser download</p>
        </div>

        <button
          onClick={handleSave}
          className="flex items-center gap-2 bg-primary-600 hover:bg-primary-700 text-white text-sm font-medium px-4 py-2 rounded-lg transition-colors"
        >
          <Save className="w-4 h-4" />
          {saved ? 'Saved!' : 'Save Settings'}
        </button>
      </div>

      {/* App Info */}
      <div className="pt-4 border-t border-gray-800 text-xs text-gray-600 space-y-1">
        <p>LanLink v1.0.0</p>
        <p>Local file transfer & messaging over WiFi</p>
        <p>© 2026 Tapiwa Makandigona</p>
      </div>
    </div>
  );
}
