/// Metadata about a single file in a transfer.
///
/// This matches the per-file shape in LocalSend's `prepare-upload` request.
class FileInfo {
  FileInfo({
    required this.id,
    required this.fileName,
    required this.size,
    required this.fileType,
    this.sha256,
    this.preview,
    this.localPath,
    this.contentUri,
  });

  /// Sender-chosen ID, unique within a session.
  final String id;
  final String fileName;
  final int size;

  /// MIME-ish type string. Common values: `image`, `video`, `app`, `text`, `pdf`, `other`.
  final String fileType;

  /// Optional SHA-256 of the file. v2.0 does not require it but will record
  /// it for verification when present.
  final String? sha256;

  /// Optional small inline preview (base64) for images. Not used by v2.0.
  final String? preview;

  /// Local filesystem path (sender-side). Receiver leaves this null and
  /// fills in the eventual save path after acceptance.
  final String? localPath;

  /// Android `content://` URI (sender-side alternative to [localPath]):
  /// SAF picks stream straight from the source provider instead of copying
  /// the file into the app cache first. Local-only — never on the wire.
  final String? contentUri;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'size': size,
        'fileType': fileType,
        if (sha256 != null) 'sha256': sha256,
        if (preview != null) 'preview': preview,
      };

  factory FileInfo.fromJson(Map<String, dynamic> json) => FileInfo(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        size: (json['size'] as num).toInt(),
        fileType: (json['fileType'] as String?) ?? 'other',
        sha256: json['sha256'] as String?,
        preview: json['preview'] as String?,
      );

  /// Total, non-throwing parse of one peer-controlled `prepare-upload` file
  /// entry. Returns null when the entry is not a JSON object or is missing
  /// the mandatory `id` / `fileName` / a non-negative `size` — a hostile or
  /// buggy peer must yield a clean rejection, never a thrown [TypeError]
  /// that turns a bad request into a 500 (or, at an unguarded call site, an
  /// unhandled async error).
  static FileInfo? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final fileName = raw['fileName'];
    if (id is! String || id.isEmpty) return null;
    if (fileName is! String || fileName.isEmpty) return null;
    final sizeRaw = raw['size'];
    int size;
    if (sizeRaw is num) {
      if (!sizeRaw.isFinite || sizeRaw != sizeRaw.truncateToDouble()) {
        return null;
      }
      size = sizeRaw.toInt();
    } else if (sizeRaw is String) {
      final parsed = int.tryParse(sizeRaw.trim());
      if (parsed == null) return null;
      size = parsed;
    } else {
      return null;
    }
    if (size < 0) return null;
    return FileInfo(
      id: id,
      fileName: fileName,
      size: size,
      fileType: raw['fileType'] is String ? raw['fileType'] as String : 'other',
      sha256: raw['sha256'] is String ? raw['sha256'] as String : null,
      preview: raw['preview'] is String ? raw['preview'] as String : null,
    );
  }

  FileInfo copyWith({String? localPath, String? contentUri}) => FileInfo(
        id: id,
        fileName: fileName,
        size: size,
        fileType: fileType,
        sha256: sha256,
        preview: preview,
        localPath: localPath ?? this.localPath,
        contentUri: contentUri ?? this.contentUri,
      );
}

/// Best-effort MIME-ish categorization from a filename extension.
String fileTypeForName(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'svg'};
  const videos = {'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'};
  const audio = {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'};
  const docs = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt'};
  const archive = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'};
  const code = {'txt', 'md', 'json', 'xml', 'yml', 'yaml', 'csv', 'log'};
  if (ext == 'apk') return 'app';
  if (images.contains(ext)) return 'image';
  if (videos.contains(ext)) return 'video';
  if (audio.contains(ext)) return 'audio';
  if (docs.contains(ext)) return 'pdf';
  if (archive.contains(ext)) return 'archive';
  if (code.contains(ext)) return 'text';
  return 'other';
}
