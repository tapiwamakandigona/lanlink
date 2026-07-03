import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

import 'app.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _unlockHighRefreshRate();
  final state = await AppState.bootstrap();
  runApp(LanLinkApp(state: state));
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
