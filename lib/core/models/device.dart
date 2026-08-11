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
  factory Device.fromJson(Map<String, dynamic> json, {required String ip}) {
    return Device(
      alias: (json['alias'] as String?)?.trim().isNotEmpty == true
          ? json['alias'] as String
          : 'Unknown device',
      version: (json['version'] as String?) ?? LanLinkProtocol.protocolVersion,
      deviceModel: (json['deviceModel'] as String?) ?? '',
      deviceType:
          (json['deviceType'] as String?) ?? LanLinkProtocol.deviceTypeHeadless,
      fingerprint: (json['fingerprint'] as String?) ?? '',
      port: (json['port'] as int?) ?? LanLinkProtocol.defaultPort,
      protocol: (json['protocol'] as String?) ?? 'https',
      ip: ip,
      announcement: json['announce'] == true,
      download: json['download'] == true,
    );
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
