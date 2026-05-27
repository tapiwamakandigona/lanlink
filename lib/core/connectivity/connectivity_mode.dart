import 'dart:io';

enum ConnectivityMode {
  lan,
  hotspot,
  bluetooth,
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
