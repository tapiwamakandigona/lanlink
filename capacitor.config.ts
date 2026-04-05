import { CapacitorConfig } from '@capacitor/cli';

/**
 * [INTENT] Capacitor config for Android mobile build
 * [CONSTRAINT] WebView connects to desktop WebSocket; needs network permissions
 */
const config: CapacitorConfig = {
  appId: 'com.lanlink.mobile',
  appName: 'LanLink',
  webDir: 'dist',
  server: {
    androidScheme: 'http',
    cleartext: true, // [EDGE-CASE] WebSocket on LAN uses ws:// not wss://
  },
  plugins: {
    CapacitorHttp: {
      enabled: false,
    },
  },
  android: {
    allowMixedContent: true,
  },
};

export default config;
