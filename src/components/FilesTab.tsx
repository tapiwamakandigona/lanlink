/**
 * [INTENT] Files tab — drag-and-drop zone, transfer queue, received files list
 * [CONSTRAINT] Must handle both drag-drop (desktop) and file picker (mobile)
 * [EDGE-CASE] Large files should show chunked progress; prevent duplicate sends
 */

import { useCallback, useRef } from 'react';
import { useApp } from '@/hooks/useAppContext';
import { Upload, FileIcon, CheckCircle, XCircle, Loader2, Pause } from 'lucide-react';
import { formatBytes, formatSpeed } from '@/lib/file-utils';
import type { FileTransfer } from '@/lib/file-utils';

export function FilesTab() {
  const { state, sendFile } = useApp();
  const fileInputRef = useRef<HTMLInputElement>(null);
  const dragCountRef = useRef(0);

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      dragCountRef.current = 0;
      const files = Array.from(e.dataTransfer.files);
      files.forEach((f) => sendFile(f));
    },
    [sendFile]
  );

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files ?? []);
    files.forEach((f) => sendFile(f));
    e.target.value = '';
  };

  const isConnected = state.connection === 'connected';

  return (
    <div className="flex flex-col gap-4 p-4 h-full overflow-y-auto">
      {/* Drop zone */}
      <div
        onDrop={handleDrop}
        onDragOver={handleDragOver}
        onClick={() => isConnected && fileInputRef.current?.click()}
        className={`border-2 border-dashed rounded-xl p-8 text-center transition-colors cursor-pointer ${
          isConnected
            ? 'border-primary-500/50 hover:border-primary-400 hover:bg-primary-500/5'
            : 'border-gray-700 opacity-50 cursor-not-allowed'
        }`}
      >
        <Upload className="w-10 h-10 mx-auto mb-3 text-primary-400" />
        <p className="text-sm text-gray-300">
          {isConnected ? 'Drop files here or click to browse' : 'Connect to a device to send files'}
        </p>
        <p className="text-xs text-gray-500 mt-1">Supports files up to 2GB</p>
        <input
          ref={fileInputRef}
          type="file"
          multiple
          onChange={handleFileSelect}
          className="hidden"
        />
      </div>

      {/* Transfer Queue */}
      {state.transfers.length > 0 && (
        <div className="space-y-2">
          <h3 className="text-sm font-medium text-gray-400">Transfers</h3>
          {state.transfers.map((t) => (
            <TransferItem key={t.id} transfer={t} />
          ))}
        </div>
      )}

      {/* Empty state */}
      {state.transfers.length === 0 && (
        <div className="flex-1 flex items-center justify-center">
          <p className="text-gray-600 text-sm">No transfers yet</p>
        </div>
      )}
    </div>
  );
}

function TransferItem({ transfer: t }: { transfer: FileTransfer }) {
  const percent = t.size > 0 ? Math.min((t.progress / t.size) * 100, 100) : 0;

  const StatusIcon = {
    pending: Loader2,
    transferring: Loader2,
    complete: CheckCircle,
    error: XCircle,
    paused: Pause,
  }[t.status];

  const statusColor = {
    pending: 'text-yellow-400',
    transferring: 'text-primary-400',
    complete: 'text-green-400',
    error: 'text-red-400',
    paused: 'text-gray-400',
  }[t.status];

  return (
    <div className="bg-gray-800/50 rounded-lg p-3 space-y-2">
      <div className="flex items-center gap-2">
        <FileIcon className="w-4 h-4 text-gray-400 flex-shrink-0" />
        <span className="text-sm text-white truncate flex-1">{t.name}</span>
        <span className="text-xs text-gray-500">{t.direction === 'send' ? '↑' : '↓'}</span>
        <StatusIcon className={`w-4 h-4 ${statusColor} ${t.status === 'transferring' || t.status === 'pending' ? 'animate-spin' : ''} flex-shrink-0`} />
      </div>

      {/* Progress bar */}
      {(t.status === 'transferring' || t.status === 'complete') && (
        <div className="w-full bg-gray-700 rounded-full h-1.5">
          <div
            className={`h-1.5 rounded-full transition-all ${t.status === 'complete' ? 'bg-green-500' : 'bg-primary-500'}`}
            style={{ width: `${percent}%` }}
          />
        </div>
      )}

      <div className="flex justify-between text-xs text-gray-500">
        <span>
          {formatBytes(t.progress)} / {formatBytes(t.size)}
        </span>
        {t.status === 'transferring' && <span>{formatSpeed(t.speed)}</span>}
        {t.status === 'error' && <span className="text-red-400">{t.error}</span>}
      </div>
    </div>
  );
}
