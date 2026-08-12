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

  // Only Android registers `lanlink/share`. Windows has no Bluetooth share
  // channel, so advertising it there turns a legacy saved preference into a
  // guaranteed MissingPluginException instead of a LAN transfer.
  static bool get supportsBluetoothShare => Platform.isAndroid;
}
