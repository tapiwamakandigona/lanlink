import 'dart:io';

enum ConnectivityMode {
  lan,
  hotspot,
  bluetooth,
}

/// Which side of a hotspot we are. Decides what subnet to scan and what
/// guidance to show the user.
enum HotspotRole {
  /// We are the device that turned on the hotspot. We sit on the AP
  /// gateway IP (typically `192.168.43.1`/`192.168.49.1`) and clients
  /// connect to us.
  hosting,

  /// We connected to someone else's hotspot. The AP host is our default
  /// gateway; everything else on the same /24 is reachable directly.
  joining,

  /// Pick automatically based on the local interface IPs at runtime.
  auto,
}

extension HotspotRoleDetails on HotspotRole {
  String get label {
    switch (this) {
      case HotspotRole.hosting:
        return "I'm hosting the hotspot";
      case HotspotRole.joining:
        return "I'm joining a hotspot";
      case HotspotRole.auto:
        return 'Detect for me';
    }
  }

  String get hint {
    switch (this) {
      case HotspotRole.hosting:
        return 'Turn on your phone\'s hotspot, then ask the other device to connect to it. We\'ll scan for them on the hotspot subnet.';
      case HotspotRole.joining:
        return 'Connect to the other device\'s hotspot from your Wi-Fi settings. We\'ll scan for the host automatically.';
      case HotspotRole.auto:
        return 'LanLink will figure out which side you\'re on based on your IP address.';
    }
  }
}

extension ConnectivityModeDetails on ConnectivityMode {
  String get label {
    switch (this) {
      case ConnectivityMode.lan:
        return 'Wi-Fi / LAN';
      case ConnectivityMode.hotspot:
        return 'Phone hotspot';
      case ConnectivityMode.bluetooth:
        return 'Bluetooth';
    }
  }

  String get description {
    switch (this) {
      case ConnectivityMode.lan:
        return 'Automatic peer discovery on the same Wi-Fi network.';
      case ConnectivityMode.hotspot:
        return 'Connect one device to the other device hotspot, then share by IP.';
      case ConnectivityMode.bluetooth:
        return 'Use the operating system Bluetooth share sheet when available.';
    }
  }

  bool get usesLanTransport => this != ConnectivityMode.bluetooth;

  bool get isAvailable {
    if (this != ConnectivityMode.bluetooth) return true;
    return Platform.isAndroid || Platform.isWindows;
  }
}
