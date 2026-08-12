import 'dart:io' show Platform;

import '../protocol/constants.dart';

/// A device participating in LanLink — either the local device or a peer.
///
/// Mirrors the shape of the LocalSend `/info` response so we interop cleanly.
class Device {
  Device({
    required this.alias,
    required this.version,
    required this.deviceModel,
    required this.deviceType,
    required this.fingerprint,
    required this.port,
    required this.protocol,
    required this.ip,
    this.announcement = false,
    this.download = false,
    this.verified = false,
  });

  /// Human-readable name shown to peers.
  final String alias;

  /// Protocol version advertised by this device.
  final String version;

  /// Model string, e.g. `"Pixel 7"` or `"Windows 11"`.
  final String deviceModel;

  /// One of [LanLinkProtocol.deviceTypeMobile], [deviceTypeDesktop], [deviceTypeHeadless].
  final String deviceType;

  /// Stable random identifier for this install. Used to detect duplicates
  /// when a peer is reachable on multiple IPs.
  final String fingerprint;

  /// HTTP port the peer is listening on.
  final int port;

  /// Wire protocol — `"http"` or `"https"`. Since protocol 2.1 every
  /// LanLink peer serves HTTPS with a self-signed pinned certificate.
  final String protocol;

  /// IP address we use to talk to this peer.
  final String ip;

  /// Whether this `/info` payload was received as an unsolicited multicast.
  final bool announcement;

  /// Whether the peer expects file downloads to also go to a download endpoint.
  /// Not used by v2.0; kept for forward compat with LocalSend "receive-only" mode.
  final bool download;

  /// Local trust flag: true when this peer's [fingerprint] has been pinned
  /// after an earlier successful connect. Never sent on the wire — a peer
  /// cannot claim to be verified; only the local pin store decides. A device
  /// announcing a familiar alias with a *different* fingerprint stays
  /// unverified.
  final bool verified;

  bool get isLocal => ip == '127.0.0.1' || ip == '0.0.0.0';

  Uri get baseUri => Uri(scheme: protocol, host: ip, port: port);

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'version': version,
        'deviceModel': deviceModel,
        'deviceType': deviceType,
        'fingerprint': fingerprint,
        'port': port,
        'protocol': protocol,
        'download': download,
        if (announcement) 'announce': true,
      };

  /// Parse a `/info` response (or multicast announcement) into a [Device].
  ///
  /// The `ip` is required because the announcement payload itself omits it
  /// (the receiver fills it from the UDP / TCP socket address).
  ///
  /// Every field is read defensively and this constructor is **total**: it
  /// never throws, whatever the peer put on the wire. The payload is fully
  /// peer-controlled (a multicast announcement, a `/info` body, a
  /// `prepare-upload` `info` object), so a value of the wrong JSON type —
  /// `port` as a string or a float, `alias` as a number — must degrade to a
  /// sane default, not a `TypeError`. A single malformed UDP announce from
  /// any device on the LAN was previously enough to throw an unhandled
  /// async error out of the discovery socket listener.
  factory Device.fromJson(Map<String, dynamic> json, {required String ip}) {
    final alias = _asString(json['alias'])?.trim();
    return Device(
      alias: (alias != null && alias.isNotEmpty) ? alias : 'Unknown device',
      version: _asString(json['version']) ?? LanLinkProtocol.protocolVersion,
      deviceModel: _asString(json['deviceModel']) ?? '',
      deviceType:
          _asString(json['deviceType']) ?? LanLinkProtocol.deviceTypeHeadless,
      fingerprint: _asString(json['fingerprint']) ?? '',
      port: _asPort(json['port']) ?? LanLinkProtocol.defaultPort,
      protocol: _asProtocol(json['protocol']),
      ip: ip,
      announcement: json['announce'] == true,
      download: json['download'] == true,
    );
  }

  /// Reads a value that should be a string, tolerating anything else by
  /// returning null (the caller supplies the default).
  static String? _asString(Object? v) => v is String ? v : null;

  /// The scheme is peer-controlled and later fed to [Uri]. Only the two
  /// transports the protocol implements are valid; everything else must
  /// fail closed to HTTPS rather than becoming `file:`, `data:`, etc.
  static String _asProtocol(Object? v) {
    if (v is! String) return 'https';
    final protocol = v.trim().toLowerCase();
    return protocol == 'http' || protocol == 'https' ? protocol : 'https';
  }

  /// Reads a TCP port that may arrive as an int, a JSON float (`53317.0`),
  /// or a numeric string (`"53317"`). Out-of-range or unparseable values
  /// return null so the default port is used instead of a bad one.
  static int? _asPort(Object? v) {
    int? n;
    if (v is int) {
      n = v;
    } else if (v is num) {
      n = v.toInt();
    } else if (v is String) {
      n = int.tryParse(v.trim());
    }
    if (n == null || n <= 0 || n > 65535) return null;
    return n;
  }

  Device copyWith({
    String? ip,
    bool? announcement,
    bool? verified,
    String? fingerprint,
  }) =>
      Device(
        alias: alias,
        version: version,
        deviceModel: deviceModel,
        deviceType: deviceType,
        fingerprint: fingerprint ?? this.fingerprint,
        port: port,
        protocol: protocol,
        ip: ip ?? this.ip,
        announcement: announcement ?? this.announcement,
        download: download,
        verified: verified ?? this.verified,
      );

  @override
  bool operator ==(Object other) =>
      other is Device && other.fingerprint == fingerprint && other.ip == ip;

  @override
  int get hashCode => Object.hash(fingerprint, ip);

  @override
  String toString() => 'Device($alias @ $ip:$port, $fingerprint)';
}

/// Detect the local device type from `Platform`.
String detectDeviceType() {
  if (Platform.isAndroid || Platform.isIOS) {
    return LanLinkProtocol.deviceTypeMobile;
  }
  return LanLinkProtocol.deviceTypeDesktop;
}

/// Detect a sensible default alias / model string.
String detectDeviceModel() {
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iOS';
  if (Platform.isWindows) return 'Windows';
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isLinux) return 'Linux';
  return 'Unknown';
}
