import 'package:flutter/foundation.dart';

/// Self-describing QR payload that LanLink encodes for instant pairing.
///
/// Looks like `lanlink://pair?ip=192.168.1.42&port=53317&alias=Pixel&fp=abcd…`.
/// The scheme is fixed so other apps don't accidentally interpret it; the
/// query string is intentionally tiny so even cheap QR scanners that downsize
/// the image can decode it.
@immutable
class PairPayload {
  const PairPayload({
    required this.ip,
    required this.port,
    required this.alias,
    this.fingerprint,
    this.ssid,
    this.password,
  });

  final String ip;
  final int port;
  final String alias;
  final String? fingerprint;

  /// Hotspot credentials for the Direct link (no shared Wi-Fi) flow.
  /// Only present when the host is running a LocalOnlyHotspot; QRs
  /// without them parse exactly as before.
  final String? ssid;
  final String? password;

  /// True when this payload carries the hotspot credentials a guest
  /// needs to join before it can reach [ip].
  bool get needsHotspotJoin => ssid != null && ssid!.isNotEmpty;

  static const String scheme = 'lanlink';
  static const String host = 'pair';

  String toQrString() {
    final params = <String, String>{
      'ip': ip,
      'port': port.toString(),
      'alias': alias,
    };
    if (fingerprint != null && fingerprint!.isNotEmpty) {
      params['fp'] = fingerprint!;
    }
    if (ssid != null && ssid!.isNotEmpty) {
      params['ssid'] = ssid!;
      params['pass'] = password ?? '';
    }
    final uri = Uri(
      scheme: scheme,
      host: host,
      queryParameters: params,
    );
    return uri.toString();
  }

  /// Returns a `PairPayload` if [raw] is a valid LanLink pair URI, else null.
  static PairPayload? tryParse(String raw) {
    if (raw.isEmpty) return null;
    final Uri uri;
    try {
      uri = Uri.parse(raw.trim());
    } catch (_) {
      return null;
    }
    if (uri.scheme != scheme || uri.host != host) return null;
    final ip = uri.queryParameters['ip'];
    final portStr = uri.queryParameters['port'];
    final alias = uri.queryParameters['alias'];
    if (ip == null || ip.isEmpty) return null;
    if (portStr == null || portStr.isEmpty) return null;
    if (alias == null || alias.isEmpty) return null;
    final port = int.tryParse(portStr);
    if (port == null || port <= 0 || port > 65535) return null;
    return PairPayload(
      ip: ip,
      port: port,
      alias: alias,
      fingerprint: uri.queryParameters['fp'],
      ssid: uri.queryParameters['ssid'],
      password: uri.queryParameters['pass'],
    );
  }

  /// Convenience for code that already knows how to add peers by host:port.
  String get hostPort => '$ip:$port';
}
