import 'package:flutter/material.dart';

import '../../../core/util/file_category.dart';

/// Maps a file name to a Material glyph via [fileCategoryFor].
///
/// Keeps icon choices in one place so consent sheets, session cards, and
/// pickers all agree on what a "video" looks like.
IconData fileGlyphFor(String fileName) => switch (fileCategoryFor(fileName)) {
      FileCategory.image => Icons.image_outlined,
      FileCategory.video => Icons.movie_outlined,
      FileCategory.audio => Icons.music_note_outlined,
      FileCategory.document => Icons.description_outlined,
      FileCategory.archive => Icons.folder_zip_outlined,
      FileCategory.apk => Icons.android_outlined,
      FileCategory.other => Icons.insert_drive_file_outlined,
    };
