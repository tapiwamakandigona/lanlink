import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AndroidAppInfo {
  const AndroidAppInfo({
    required this.label,
    required this.packageName,
    required this.apkPath,
    required this.size,
    this.icon,
  });

  final String label;
  final String packageName;
  final String apkPath;
  final int size;

  /// Launcher icon as a small PNG, when the platform side could draw it.
  final Uint8List? icon;

  factory AndroidAppInfo.fromMap(Map<dynamic, dynamic> map) {
    return AndroidAppInfo(
      label: (map['label'] as String?)?.trim().isNotEmpty == true
          ? map['label'] as String
          : map['packageName'] as String,
      packageName: map['packageName'] as String,
      apkPath: map['apkPath'] as String,
      size: (map['size'] as num).toInt(),
      icon: map['icon'] as Uint8List?,
    );
  }
}

class AndroidApps {
  static const _channel = MethodChannel('lanlink/android_apps');

  /// Test-only override so widget tests and goldens can render the
  /// Android experience on any host platform.
  @visibleForTesting
  static bool debugForceSupported = false;

  static bool get isSupported => debugForceSupported || Platform.isAndroid;

  static Future<List<AndroidAppInfo>> listLaunchableApps() async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<dynamic>('listApps');
    if (raw == null) return const [];
    return raw
        .map((e) => AndroidAppInfo.fromMap(e as Map<dynamic, dynamic>))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  /// Fetches one app's launcher icon as a small PNG. Returns null when the
  /// platform can't draw it. Kept separate from [listLaunchableApps] so the
  /// list itself stays instant; callers cache per package name.
  static Future<Uint8List?> appIcon(String packageName) async {
    if (!isSupported) return null;
    try {
      return await _channel
          .invokeMethod<Uint8List>('appIcon', {'packageName': packageName});
    } catch (_) {
      return null;
    }
  }
}
