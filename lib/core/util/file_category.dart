/// Coarse file categories used to pick glyphs in file lists.
///
/// Pure Dart (no Flutter imports) so it stays unit-testable; UI layers map
/// each category to an icon. Categorisation is by extension only — cheap,
/// offline, and good enough for a consent preview.
enum FileCategory { image, video, audio, document, archive, apk, other }

const _imageExts = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'avif', 'svg',
  'tif', 'tiff', 'raw', 'dng', //
};
const _videoExts = {
  'mp4', 'mov', 'mkv', 'webm', 'avi', 'm4v', '3gp', 'wmv', 'flv', 'ts', //
};
const _audioExts = {
  'mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'opus', 'wma', 'mid', 'amr', //
};
const _documentExts = {
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'rtf',
  'odt', 'ods', 'odp', 'csv', 'epub', //
};
const _archiveExts = {
  'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'zst', 'iso', //
};

/// Categorises [fileName] by its extension (case-insensitive).
FileCategory fileCategoryFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return FileCategory.other;
  final ext = fileName.substring(dot + 1).toLowerCase();
  if (_imageExts.contains(ext)) return FileCategory.image;
  if (_videoExts.contains(ext)) return FileCategory.video;
  if (_audioExts.contains(ext)) return FileCategory.audio;
  if (_documentExts.contains(ext)) return FileCategory.document;
  if (_archiveExts.contains(ext)) return FileCategory.archive;
  if (ext == 'apk' || ext == 'aab') return FileCategory.apk;
  return FileCategory.other;
}
