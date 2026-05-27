import 'dart:io';

import 'package:flutter/services.dart';

class PlatformShare {
  static const _channel = MethodChannel('lanlink/share');

  static Future<bool> shareFiles({
    required List<String> paths,
    String? subject,
    String? text,
  }) async {
    if (paths.isEmpty) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('shareFiles', {
        'paths': paths,
        'subject': subject,
        'text': text,
      });
      return ok == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> shareViaBluetooth({
    required List<String> paths,
  }) {
    return shareFiles(
      paths: paths,
      subject: 'LanLink Bluetooth transfer',
      text: 'Shared with LanLink',
    );
  }

  static bool get supportsBluetoothShare =>
      Platform.isAndroid || Platform.isWindows;
}
