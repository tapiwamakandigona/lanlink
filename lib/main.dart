import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _unlockHighRefreshRate();
  await _setUpDesktopWindow();
  final state = await AppState.bootstrap();
  runApp(LanLinkApp(state: state));
}

/// Desktop windows get a sensible default and a floor: without a minimum
/// size the window can be dragged down to an unusable sliver, and the OS
/// default initial size ignores our phone-first layout (~480dp content
/// column plus breathing room).
Future<void> _setUpDesktopWindow() async {
  if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    return;
  }
  try {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(560, 780),
      minimumSize: Size(400, 560),
      center: true,
      title: 'LanLink',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } catch (_) {
    // A window-chrome failure must never block startup.
  }
}

/// Many Android OEMs run Flutter at 60 Hz even on 90/120 Hz panels; asking
/// for the highest refresh rate is a cheap perceived-smoothness win.
/// Android-only, fire-and-forget: a failure (odd OEM, emulator) just leaves
/// the default mode in place.
void _unlockHighRefreshRate() {
  if (kIsWeb || !Platform.isAndroid) return;
  unawaited(() async {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (_) {
      // Best effort only — never block or crash startup over a display mode.
    }
  }());
}
