import 'dart:io';

/// Returns all non-loopback IPv4 addresses, with the most likely-routable
/// interface first.
///
/// We bind the HTTP server to `0.0.0.0` so it accepts on all of them, but we
/// still use this list to advertise a primary IP in the UI and to pick a
/// sensible broadcast interface for multicast announcements.
Future<List<String>> listLocalIPv4Addresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );

  // Rank interfaces so wired/wireless LAN bubbles to the top.
  int rank(NetworkInterface i) {
    final n = i.name.toLowerCase();
    if (n.contains('wlan') || n.contains('wi-fi') || n.contains('wifi')) {
      return 0;
    }
    if (n.contains('eth') || n.contains('en')) return 1;
    if (n.contains('vmware') || n.contains('vbox') || n.contains('docker')) {
      return 10;
    }
    return 5;
  }

  interfaces.sort((a, b) => rank(a).compareTo(rank(b)));

  return [
    for (final iface in interfaces)
      for (final addr in iface.addresses)
        if (!addr.isLoopback) addr.address,
  ];
}

/// Best-guess primary local IP, or `127.0.0.1` if no LAN interface is up.
Future<String> primaryLocalIPv4() async {
  final ips = await listLocalIPv4Addresses();
  return ips.isEmpty ? '127.0.0.1' : ips.first;
}
