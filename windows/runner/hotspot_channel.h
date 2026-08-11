#ifndef RUNNER_HOTSPOT_CHANNEL_H_
#define RUNNER_HOTSPOT_CHANNEL_H_

#include <flutter/flutter_engine.h>

#include <functional>

// Runs |task| on the platform (UI) thread. Wired up by FlutterWindow using a
// PostMessage(WM_APP + 0x40) trampoline — flutter::MethodResult must only be
// completed on the platform thread, but all WinRT work happens on workers.
using MainThreadDispatcher = std::function<void(std::function<void()>)>;

namespace hotspot_channel {

// Registers the "lanlink/hotspot" MethodChannel on |engine|.
void Register(flutter::FlutterEngine* engine, MainThreadDispatcher dispatcher);

// Best-effort teardown on app exit (stops the Wi-Fi Direct publisher or the
// tethering session we started). Safe to call from the platform thread.
void Shutdown();

}  // namespace hotspot_channel

#endif  // RUNNER_HOTSPOT_CHANNEL_H_
