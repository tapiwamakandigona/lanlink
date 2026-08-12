/// Helpers for moving folder structures across the wire safely.
///
/// When a whole folder is sent, each file's `fileName` carries its relative
/// path with `/` separators (e.g. `Holiday/IMG_001.jpg`). The receiving
/// side must never let that string escape the save directory or smuggle in
/// characters the local filesystem rejects.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

const _illegal = r'[\\/:*?"<>|]';

/// Control characters (0x00–0x1F) are rejected by Windows and are at best
/// invisible landmines elsewhere.
final _controlChars = RegExp(r'[\x00-\x1f]');

/// Windows reserved device names — invalid as a file's base name in any
/// directory, with or without an extension (`CON`, `con.txt`, `Lpt1.log`).
/// Writing to them fails or, worse, addresses the actual device.
final _windowsReserved = RegExp(
  r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
  caseSensitive: false,
);

/// Splits a wire `fileName` into sanitized path segments.
///
/// - Accepts both `/` and `\` as separators.
/// - Drops empty, `.`, and `..` segments (no path traversal).
/// - Replaces characters that are illegal on common filesystems, including
///   control characters.
/// - Neutralizes Windows reserved device names (`CON`, `NUL`, `COM1`…,
///   with or without extension) by prefixing an underscore.
/// - Strips trailing dots and spaces (invalid on Windows, confusing
///   everywhere).
/// - Always returns at least one segment; a degenerate input collapses to
///   `file`.
List<String> splitSafeRelativePath(String fileName) {
  final segments = <String>[];
  for (final raw in fileName.split(RegExp(r'[/\\]'))) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') continue;
    var safe =
        trimmed.replaceAll(_controlChars, '').replaceAll(RegExp(_illegal), '_');
    // Windows rejects names ending in a dot or space; strip them after the
    // character replacement so "file.<illegal>" cannot re-grow one.
    safe = safe.replaceAll(RegExp(r'[. ]+$'), '');
    if (safe.isEmpty) continue;
    if (_windowsReserved.hasMatch(safe)) safe = '_$safe';
    segments.add(clampFileNameSegment(safe));
  }
  if (segments.isEmpty) return const ['file'];
  return segments;
}

/// Clamps one path segment to a filesystem-safe byte length.
///
/// Most filesystems cap a single name at 255 bytes; the receiver also
/// prepends part-file prefixes and " (1)" dedup suffixes, so we clamp well
/// below that. Over-long names are truncated (preserving a reasonable
/// extension) and suffixed with a short hash of the original so two
/// distinct long names never collapse into the same file. A peer sending a
/// 1000-char filename used to sail through prepare-upload and then blow up
/// the upload with ENAMETOOLONG (surfaced as a 500).
String clampFileNameSegment(String name, {int maxBytes = 180}) {
  if (utf8.encode(name).length <= maxBytes) return name;
  final digest = sha1.convert(utf8.encode(name)).toString().substring(0, 8);
  final dot = name.lastIndexOf('.');
  // Keep the extension only when it looks like one (short, not the whole
  // name) so `.hidden`-style or dotless names degrade gracefully.
  var ext = '';
  var base = name;
  if (dot > 0 && name.length - dot <= 16) {
    ext = name.substring(dot);
    base = name.substring(0, dot);
  }
  // Reserve room for "~<hash>" + extension, then trim the base by whole
  // code units until it fits in bytes.
  final budget = maxBytes - utf8.encode('~$digest$ext').length;
  var keep = base.length < budget ? base.length : budget;
  while (keep > 0 && utf8.encode(base.substring(0, keep)).length > budget) {
    keep--;
  }
  return '${base.substring(0, keep)}~$digest$ext';
}
