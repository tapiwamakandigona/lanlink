import 'dart:io';

/// Opens [folder] in the platform file manager (desktop only).
///
/// Competing tools (AirDrop's "Show in Finder", Quick Share's "Open
/// folder") jump straight to the received files; a copyable path is a
/// consolation prize. Mobile platforms return false — sandboxed file
/// paths are not user-navigable there and the Downloads publish already
/// covers Android.
Future<bool> revealFolder(String folder) async {
  final cmd = revealCommandFor(Platform.operatingSystem, folder);
  if (cmd == null) return false;
  try {
    await Process.start(
      cmd.first,
      cmd.sublist(1),
      mode: ProcessStartMode.detached,
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// The file-manager command for [os] ('windows'|'macos'|'linux'), or null
/// when the platform has no user-navigable file manager. Pure so it can be
/// unit-tested on any host.
List<String>? revealCommandFor(String os, String folder) {
  switch (os) {
    case 'windows':
      return ['explorer', folder];
    case 'macos':
      return ['open', folder];
    case 'linux':
      return ['xdg-open', folder];
    default:
      return null;
  }
}
