import 'package:flutter/foundation.dart';

import 'pair_payload.dart';

/// QR payload for the Simple-mode connect-first flow.
///
/// Two shapes share one scheme so the scanner needs a single parser:
///
/// * Same Wi-Fi: `lanlink://connect?ip=…&port=…&alias=…&fp=…`
///   — the sender connects straight away.
/// * No Wi-Fi (receiver hosts a hotspot):
///   `lanlink://connect?ip=…&port=…&alias=…&fp=…&ssid=…&pass=…`
///   — the sender's phone first joins the hotspot, then connects.
///
/// Legacy `lanlink://pair` QRs (full-mode pairing sheet) are accepted too,
/// so a Simple-mode sender can scan a full-mode receiver's code.
@immutable
class ConnectPayload {
  const ConnectPayload({
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

  /// Hotspot credentials; non-null only for the no-Wi-Fi shape.
  final String? ssid;
  final String? password;

  static const String scheme = 'lanlink';
  static const String host = 'connect';

  bool get needsHotspotJoin => ssid != null && ssid!.isNotEmpty;

  String get hostPort => '$ip:$port';

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
    return Uri(scheme: scheme, host: host, queryParameters: params).toString();
  }

  /// Parses `lanlink://connect` URIs, falling back to legacy
  /// `lanlink://pair` codes. Returns null for anything else.
  static ConnectPayload? tryParse(String raw) {
    if (raw.isEmpty) return null;
    final Uri uri;
    try {
      uri = Uri.parse(raw.trim());
    } catch (_) {
      return null;
    }
    if (uri.scheme == PairPayload.scheme && uri.host == PairPayload.host) {
      final pair = PairPayload.tryParse(raw);
      if (pair == null) return null;
      return ConnectPayload(
        ip: pair.ip,
        port: pair.port,
        alias: pair.alias,
        fingerprint: pair.fingerprint,
      );
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
    return ConnectPayload(
      ip: ip,
      port: port,
      alias: alias,
      fingerprint: uri.queryParameters['fp'],
      ssid: uri.queryParameters['ssid'],
      password: uri.queryParameters['pass'],
    );
  }
}
