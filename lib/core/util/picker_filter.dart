import '../platform/android_apps.dart';
import '../platform/media_library.dart';

/// Pure helpers behind the share picker: search filtering, selection
/// totals, and the "Move my photos" camera-roll bundle. Kept free of
/// widgets/platform calls so they're trivially unit-testable.

/// Case-insensitive substring match on app label and package name.
List<AndroidAppInfo> filterApps(List<AndroidAppInfo> apps, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return apps;
  return [
    for (final app in apps)
      if (app.label.toLowerCase().contains(q) ||
          app.packageName.toLowerCase().contains(q))
        app,
  ];
}

/// Case-insensitive substring match on file name and album (bucket) name.
List<MediaItem> filterMedia(List<MediaItem> items, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  return [
    for (final item in items)
      if (item.name.toLowerCase().contains(q) ||
          item.bucket.toLowerCase().contains(q))
        item,
  ];
}

/// Camera-roll subset used by one-tap photo migration: everything shot
/// with the camera (bucket "Camera" or stored under DCIM). Falls back to
/// all media when the device uses a non-standard camera bucket.
List<MediaItem> cameraRoll(List<MediaItem> items) {
  final camera = [
    for (final item in items)
      if (item.bucket.toLowerCase() == 'camera' || item.path.contains('/DCIM/'))
        item,
  ];
  return camera.isEmpty ? items : camera;
}

/// Total byte size of a media selection.
int mediaTotalSize(Iterable<MediaItem> items) =>
    items.fold(0, (sum, item) => sum + item.size);

/// Total byte size of an app selection.
int appsTotalSize(Iterable<AndroidAppInfo> apps) =>
    apps.fold(0, (sum, app) => sum + app.size);
