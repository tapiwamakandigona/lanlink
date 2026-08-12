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
    this.isSplitInstall = false,
    this.icon,
  });

  final String label;
  final String packageName;
  final String apkPath;
  final int size;

  /// Whether Android installed this package as a base APK plus splits.
  /// Sharing only [apkPath] would yield an incomplete, non-installable app.
  final bool isSplitInstall;

  /// Launcher icon as a small PNG, when the platform side could draw it.
  final Uint8List? icon;

  static AndroidAppInfo? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final packageName = raw['packageName'];
    final apkPath = raw['apkPath'];
    final size = raw['size'];
    if (packageName is! String ||
        packageName.isEmpty ||
        apkPath is! String ||
        apkPath.isEmpty ||
        size is! num ||
        !size.isFinite ||
        size != size.truncateToDouble() ||
        size < 0) {
      return null;
    }
    final label = raw['label'];
    return AndroidAppInfo(
      label: label is String && label.trim().isNotEmpty ? label : packageName,
      packageName: packageName,
      apkPath: apkPath,
      size: size.toInt(),
      isSplitInstall: raw['isSplitInstall'] == true,
      icon: raw['icon'] is Uint8List ? raw['icon'] as Uint8List : null,
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
        .map(AndroidAppInfo.tryFromMap)
        .whereType<AndroidAppInfo>()
        .toList(growable: false)
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
