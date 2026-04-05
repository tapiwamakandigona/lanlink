/**
 * [INTENT] Main App component with sidebar + tabbed layout
 * [CONSTRAINT] Must be responsive — sidebar on top (mobile) or left (desktop)
 */

import { useState } from 'react';
import { AppProvider } from '@/hooks/useAppContext';
import { Sidebar } from '@/components/Sidebar';
import { FilesTab } from '@/components/FilesTab';
import { ChatTab } from '@/components/ChatTab';
import { SettingsTab } from '@/components/SettingsTab';
import { FolderOpen, MessageCircle, Settings } from 'lucide-react';
import type { TabId } from '@/types';

const tabs: { id: TabId; label: string; Icon: typeof FolderOpen }[] = [
  { id: 'files', label: 'Files', Icon: FolderOpen },
  { id: 'chat', label: 'Chat', Icon: MessageCircle },
  { id: 'settings', label: 'Settings', Icon: Settings },
];

function AppContent() {
  const [activeTab, setActiveTab] = useState<TabId>('files');

  return (
    <div className="h-screen flex flex-col lg:flex-row bg-gray-950 text-gray-100">
      <Sidebar />

      <div className="flex-1 flex flex-col min-h-0">
        {/* Tab Bar */}
        <div className="flex border-b border-gray-800 bg-gray-900/50">
          {tabs.map(({ id, label, Icon }) => (
            <button
              key={id}
              onClick={() => setActiveTab(id)}
              className={`flex items-center gap-2 px-4 py-3 text-sm font-medium transition-colors border-b-2 ${
                activeTab === id
                  ? 'text-primary-400 border-primary-500'
                  : 'text-gray-500 border-transparent hover:text-gray-300'
              }`}
            >
              <Icon className="w-4 h-4" />
              <span className="hidden sm:inline">{label}</span>
            </button>
          ))}
        </div>

        {/* Tab Content */}
        <div className="flex-1 min-h-0">
          {activeTab === 'files' && <FilesTab />}
          {activeTab === 'chat' && <ChatTab />}
          {activeTab === 'settings' && <SettingsTab />}
        </div>
      </div>
    </div>
  );
}

export default function App() {
  return (
    <AppProvider>
      <AppContent />
    </AppProvider>
  );
}
