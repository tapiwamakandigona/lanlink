import '../models/file_info.dart';

/// Builds a plain-language description of a file list for Simple mode:
/// "3 photos", "1 video", "2 photos and 1 video", "5 files".
///
/// Photos-first phrasing is deliberate — non-technical users think in
/// photos and videos, not "files" or megabytes.
String describeFilesFriendly(List<FileInfo> files) {
  if (files.isEmpty) return 'nothing';
  var photos = 0;
  var videos = 0;
  var other = 0;
  for (final f in files) {
    switch (f.fileType) {
      case 'image':
        photos++;
      case 'video':
        videos++;
      default:
        other++;
    }
  }
  final parts = <String>[
    if (photos > 0) photos == 1 ? '1 photo' : '$photos photos',
    if (videos > 0) videos == 1 ? '1 video' : '$videos videos',
  ];
  if (other > 0) {
    // Mixed bag: if everything is "other", call them files; if mixed with
    // media, mention them as files too ("2 photos and 1 file").
    parts.add(other == 1 ? '1 file' : '$other files');
  }
  if (parts.length == 1) return parts.first;
  if (parts.length == 2) return '${parts[0]} and ${parts[1]}';
  return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}
