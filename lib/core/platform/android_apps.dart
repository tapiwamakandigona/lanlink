import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class AndroidAppInfo {
  const AndroidAppInfo({
    required this.label,
    required this.packageName,
    required this.apkPath,
    required this.size,
  });

  final String label;
  final String packageName;
  final String apkPath;
  final int size;

  factory AndroidAppInfo.fromMap(Map<dynamic, dynamic> map) {
    return AndroidAppInfo(
      label: (map['label'] as String?)?.trim().isNotEmpty == true
          ? map['label'] as String
          : map['packageName'] as String,
      packageName: map['packageName'] as String,
      apkPath: map['apkPath'] as String,
      size: (map['size'] as num).toInt(),
    );
  }
}

class AndroidApps {
  static const _channel = MethodChannel('lanlink/android_apps');

  static bool get isSupported => Platform.isAndroid;

  static Future<List<AndroidAppInfo>> listLaunchableApps() async {
    if (!isSupported) return const [];
    final raw = await _channel.invokeListMethod<dynamic>('listApps');
    if (raw == null) return const [];
    return raw
        .map((e) => AndroidAppInfo.fromMap(e as Map<dynamic, dynamic>))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }
}
