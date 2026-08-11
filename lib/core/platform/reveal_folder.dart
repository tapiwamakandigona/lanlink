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

/// Opens [file] with the platform's default application (desktop only).
///
/// AirDrop and Quick Share open a just-received file in one tap; this is
/// the desktop equivalent. Mobile returns false — the Downloads publish
/// (Android) and share sheet cover it there.
Future<bool> openFile(String file) async {
  final cmd = openFileCommandFor(Platform.operatingSystem, file);
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

/// The default-app open command for [os], or null when unsupported. On
/// Windows `explorer <file>` opens it with the associated app without
/// needing a shell (`start` is a cmd builtin). Pure for unit tests.
List<String>? openFileCommandFor(String os, String file) {
  switch (os) {
    case 'windows':
      return ['explorer', file];
    case 'macos':
      return ['open', file];
    case 'linux':
      return ['xdg-open', file];
    default:
      return null;
  }
}
