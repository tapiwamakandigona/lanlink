/**
 * [INTENT] Chat tab — simple message bubbles with clipboard sharing
 * [CONSTRAINT] Session-only history (no persistence)
 * [EDGE-CASE] Handle empty messages, rapid sends, very long text
 */

import { useState, useRef, useEffect } from 'react';
import { useApp } from '@/hooks/useAppContext';
import { Send, Clipboard } from 'lucide-react';

export function ChatTab() {
  const { state, sendChat, sendClipboard } = useApp();
  const [input, setInput] = useState('');
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const isConnected = state.connection === 'connected';

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [state.chat]);

  const handleSend = () => {
    const text = input.trim();
    if (!text || !isConnected) return;
    sendChat(text);
    setInput('');
  };

  const handleClipboard = async () => {
    try {
      const text = await navigator.clipboard.readText();
      if (text) {
        sendClipboard(text);
        sendChat(`📋 Shared clipboard: ${text.slice(0, 100)}${text.length > 100 ? '...' : ''}`);
      }
    } catch {
      // Clipboard API requires user gesture / permission
    }
  };

  return (
    <div className="flex flex-col h-full">
      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-4 space-y-3">
        {state.chat.length === 0 && (
          <div className="flex items-center justify-center h-full">
            <p className="text-gray-600 text-sm">
              {isConnected ? 'Send a message to start chatting' : 'Connect to a device to chat'}
            </p>
          </div>
        )}
        {state.chat.map((msg) => (
          <div
            key={msg.id}
            className={`flex ${msg.sender === 'local' ? 'justify-end' : 'justify-start'}`}
          >
            <div
              className={`max-w-[75%] rounded-2xl px-4 py-2 text-sm ${
                msg.sender === 'local'
                  ? 'bg-primary-600 text-white rounded-br-md'
                  : 'bg-gray-800 text-gray-200 rounded-bl-md'
              }`}
            >
              <p className="break-words whitespace-pre-wrap">{msg.content}</p>
              <p className={`text-xs mt-1 ${msg.sender === 'local' ? 'text-primary-200' : 'text-gray-500'}`}>
                {new Date(msg.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
              </p>
            </div>
          </div>
        ))}
        <div ref={messagesEndRef} />
      </div>

      {/* Input */}
      <div className="p-3 border-t border-gray-800 bg-gray-900/50">
        <div className="flex items-center gap-2">
          <button
            onClick={handleClipboard}
            disabled={!isConnected}
            className="p-2 text-gray-400 hover:text-primary-400 disabled:opacity-50 transition-colors"
            title="Share clipboard"
          >
            <Clipboard className="w-5 h-5" />
          </button>
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && handleSend()}
            placeholder={isConnected ? 'Type a message...' : 'Not connected'}
            disabled={!isConnected}
            className="flex-1 bg-gray-800 border border-gray-700 rounded-full px-4 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-primary-500 disabled:opacity-50"
          />
          <button
            onClick={handleSend}
            disabled={!isConnected || !input.trim()}
            className="p-2 text-primary-400 hover:text-primary-300 disabled:opacity-50 transition-colors"
          >
            <Send className="w-5 h-5" />
          </button>
        </div>
      </div>
    </div>
  );
}
