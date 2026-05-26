import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

const _fingerprintKey = 'lanlink_fingerprint';

/// Returns a stable, per-install device fingerprint.
///
/// On first run we generate 16 random bytes and persist them in
/// SharedPreferences. Subsequent calls return the same value. The
/// fingerprint is used by peers to detect duplicate announcements when
/// the same device is reachable on multiple IPs.
Future<String> loadOrCreateFingerprint() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_fingerprintKey);
  if (existing != null && existing.isNotEmpty) return existing;

  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  final fp = base64Url.encode(bytes).replaceAll('=', '');
  await prefs.setString(_fingerprintKey, fp);
  return fp;
}
