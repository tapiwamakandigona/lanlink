/// Helpers for moving folder structures across the wire safely.
///
/// When a whole folder is sent, each file's `fileName` carries its relative
/// path with `/` separators (e.g. `Holiday/IMG_001.jpg`). The receiving
/// side must never let that string escape the save directory or smuggle in
/// characters the local filesystem rejects.
library;

const _illegal = r'[\\/:*?"<>|]';

/// Splits a wire `fileName` into sanitized path segments.
///
/// - Accepts both `/` and `\` as separators.
/// - Drops empty, `.`, and `..` segments (no path traversal).
/// - Replaces characters that are illegal on common filesystems.
/// - Always returns at least one segment; a degenerate input collapses to
///   `file`.
List<String> splitSafeRelativePath(String fileName) {
  final segments = <String>[];
  for (final raw in fileName.split(RegExp(r'[/\\]'))) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..') continue;
    final safe = trimmed.replaceAll(RegExp(_illegal), '_');
    if (safe.isEmpty) continue;
    segments.add(safe);
  }
  if (segments.isEmpty) return const ['file'];
  return segments;
}
