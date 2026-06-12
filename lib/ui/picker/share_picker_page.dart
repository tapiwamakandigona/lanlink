import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/file_info.dart';
import '../../core/platform/android_apps.dart';
import '../../core/platform/media_library.dart';
import '../../core/util/format.dart';
import '../../core/util/picker_filter.dart';

const _uuid = Uuid();

/// Which tab the picker opens on.
enum SharePickerTab { photos, apps }

/// Full-screen picker for photos, videos and installed apps — the
/// SHAREit-style selection surface. Multi-select with a running total,
/// search across both tabs, and a single "Add" action that returns the
/// selection as ready-to-stage [FileInfo]s.
///
/// Data sources are injectable so widget tests can drive the page
/// without real platform channels.
class SharePickerPage extends StatefulWidget {
  const SharePickerPage({
    super.key,
    this.initialTab = SharePickerTab.photos,
    this.loadMedia = MediaLibrary.listMedia,
    this.loadApps = AndroidApps.listLaunchableApps,
    this.thumbnailLoader = _defaultThumbnail,
    this.appIconLoader = AndroidApps.appIcon,
  });

  final SharePickerTab initialTab;
  final Future<List<MediaItem>> Function() loadMedia;
  final Future<List<AndroidAppInfo>> Function() loadApps;
  final Future<Uint8List?> Function(MediaItem item) thumbnailLoader;

  /// Lazily fetches one app's launcher icon. Icons are deliberately not
  /// part of [loadApps] any more: rasterising hundreds of icons up front
  /// was what made the Apps tab feel slow.
  final Future<Uint8List?> Function(String packageName) appIconLoader;

  static Future<Uint8List?> _defaultThumbnail(MediaItem item) =>
      MediaLibrary.thumbnail(item.id, isVideo: item.isVideo);

  /// Opens the picker and returns the staged files, or null on cancel.
  static Future<List<FileInfo>?> open(
    BuildContext context, {
    SharePickerTab initialTab = SharePickerTab.photos,
  }) {
    return Navigator.of(context).push<List<FileInfo>>(
      MaterialPageRoute(
        builder: (_) => SharePickerPage(initialTab: initialTab),
      ),
    );
  }

  @override
  State<SharePickerPage> createState() => _SharePickerPageState();
}

class _SharePickerPageState extends State<SharePickerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchController = TextEditingController();
  final _thumbCache = <int, Future<Uint8List?>>{};
  final _iconCache = <String, Future<Uint8List?>>{};

  List<MediaItem>? _media;
  List<AndroidAppInfo>? _apps;
  bool _mediaFailed = false;
  bool _appsFailed = false;

  final _selectedMedia = <int, MediaItem>{};
  final _selectedApps = <String, AndroidAppInfo>{};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab == SharePickerTab.photos ? 0 : 1,
    );
    _load();
  }

  /// Photos and apps load independently so the faster tab paints as soon
  /// as its data arrives instead of waiting for the slower one.
  void _load() {
    unawaited(() async {
      try {
        final media = await widget.loadMedia();
        if (!mounted) return;
        setState(() => _media = media);
      } catch (_) {
        if (!mounted) return;
        setState(() => _mediaFailed = true);
      }
    }());
    unawaited(() async {
      try {
        final apps = await widget.loadApps();
        if (!mounted) return;
        setState(() => _apps = apps);
      } catch (_) {
        if (!mounted) return;
        setState(() => _appsFailed = true);
      }
    }());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  int get _selectedCount => _selectedMedia.length + _selectedApps.length;

  int get _selectedBytes =>
      mediaTotalSize(_selectedMedia.values) +
      appsTotalSize(_selectedApps.values);

  List<FileInfo> _buildSelection() {
    return [
      for (final item in _selectedMedia.values)
        FileInfo(
          id: _uuid.v4(),
          fileName: item.name,
          size: item.size,
          fileType: fileTypeForName(item.name),
          localPath: item.path,
        ),
      for (final app in _selectedApps.values)
        FileInfo(
          id: _uuid.v4(),
          fileName: '${safeApkName(app.label)}.apk',
          size: app.size,
          fileType: 'app',
          localPath: app.apkPath,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _searchController.text;
    final media = filterMedia(_media ?? const [], query);
    final apps = filterApps(_apps ?? const [], query);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick what to send'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(
              icon: Icon(Icons.photo_library_outlined),
              text: 'Photos & videos',
            ),
            Tab(icon: Icon(Icons.apps), text: 'Apps'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              key: const Key('picker-search'),
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search by name…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _photosTab(theme, media),
                _appsTab(theme, apps),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedCount == 0
                      ? 'Nothing selected yet'
                      : '$_selectedCount item${_selectedCount == 1 ? '' : 's'}'
                          ' • ${formatBytes(_selectedBytes)}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              FilledButton.icon(
                key: const Key('picker-add'),
                onPressed: _selectedCount == 0
                    ? null
                    : () => Navigator.of(context).pop(_buildSelection()),
                icon: const Icon(Icons.add),
                label: Text(
                  _selectedCount == 0 ? 'Add' : 'Add $_selectedCount',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(ThemeData theme, IconData icon, String message,
      {bool failed = false}) {
    if (failed) {
      return Center(
        child: Text(
          'Could not read the library.\nCheck the media permission in '
          'system settings and try again.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  // ----- Photos & videos -----

  Widget _photosTab(ThemeData theme, List<MediaItem> media) {
    if (_media == null && !_mediaFailed) {
      return const Center(child: CircularProgressIndicator());
    }
    if (media.isEmpty) {
      return _emptyState(
        theme,
        Icons.photo_library_outlined,
        'No photos or videos found.',
        failed: _mediaFailed,
      );
    }
    final allSelected = media.isNotEmpty &&
        media.every((m) => _selectedMedia.containsKey(m.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '${media.length} item${media.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              TextButton.icon(
                key: const Key('picker-select-all'),
                onPressed: () => setState(() {
                  if (allSelected) {
                    for (final m in media) {
                      _selectedMedia.remove(m.id);
                    }
                  } else {
                    for (final m in media) {
                      _selectedMedia[m.id] = m;
                    }
                  }
                }),
                icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                label: Text(allSelected ? 'Deselect all' : 'Select all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 110,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: media.length,
            itemBuilder: (context, i) => _mediaTile(theme, media[i]),
          ),
        ),
      ],
    );
  }

  Widget _mediaTile(ThemeData theme, MediaItem item) {
    final selected = _selectedMedia.containsKey(item.id);
    return InkWell(
      key: Key('media-${item.id}'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() {
        if (selected) {
          _selectedMedia.remove(item.id);
        } else {
          _selectedMedia[item.id] = item;
        }
      }),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: FutureBuilder<Uint8List?>(
              future: _thumbCache.putIfAbsent(
                item.id,
                () => widget.thumbnailLoader(item),
              ),
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) {
                  return Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      item.isVideo
                          ? Icons.videocam_outlined
                          : Icons.image_outlined,
                      color: theme.colorScheme.outline,
                    ),
                  );
                }
                return Image.memory(bytes,
                    fit: BoxFit.cover, gaplessPlayback: true);
              },
            ),
          ),
          if (item.isVideo)
            const Positioned(
              left: 6,
              bottom: 6,
              child:
                  Icon(Icons.play_circle_fill, size: 18, color: Colors.white),
            ),
          Positioned(
            right: 4,
            top: 4,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? theme.colorScheme.primary : Colors.black54,
              ),
              padding: const EdgeInsets.all(2),
              child: Icon(
                selected ? Icons.check : Icons.circle_outlined,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
          if (selected)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 2.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ----- Apps -----

  Widget _appsTab(ThemeData theme, List<AndroidAppInfo> apps) {
    if (_apps == null && !_appsFailed) {
      return const Center(child: CircularProgressIndicator());
    }
    if (apps.isEmpty) {
      return _emptyState(theme, Icons.apps, 'No shareable apps found.',
          failed: _appsFailed);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
      itemCount: apps.length,
      itemBuilder: (context, i) {
        final app = apps[i];
        final selected = _selectedApps.containsKey(app.packageName);
        return CheckboxListTile(
          key: Key('app-${app.packageName}'),
          value: selected,
          onChanged: (checked) => setState(() {
            if (checked == true) {
              _selectedApps[app.packageName] = app;
            } else {
              _selectedApps.remove(app.packageName);
            }
          }),
          secondary: _appIcon(theme, app),
          title: Text(app.label, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${app.packageName} • ${formatBytes(app.size)}',
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  /// Lazily loaded launcher icon: the list paints instantly and icons
  /// stream in as rows become visible (same pattern as photo thumbnails).
  Widget _appIcon(ThemeData theme, AndroidAppInfo app) {
    final placeholder = CircleAvatar(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.android),
    );
    if (app.icon != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(app.icon!, width: 40, height: 40),
      );
    }
    final future = _iconCache.putIfAbsent(
      app.packageName,
      () => widget.appIconLoader(app.packageName),
    );
    return SizedBox(
      width: 40,
      height: 40,
      child: FutureBuilder<Uint8List?>(
        future: future,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) return placeholder;
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, width: 40, height: 40),
          );
        },
      ),
    );
  }
}

/// Filesystem-safe APK file name from an app label (same sanitisation the
/// legacy APK dialog used, so file names stay consistent across versions).
String safeApkName(String label) {
  final cleaned = label.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
  return cleaned.isEmpty ? 'app' : cleaned;
}
