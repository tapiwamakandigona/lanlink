import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/file_info.dart';
import '../../core/platform/android_apps.dart';
import '../../core/platform/media_library.dart';
import '../../core/platform/media_permissions.dart';
import '../../core/util/format.dart';
import '../../core/util/picker_filter.dart';
import '../v4/theme/tokens.dart';

const _uuid = Uuid();

/// Which tab the picker opens on.
enum SharePickerTab { photos, apps, files }

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
    this.requestMediaAccess = MediaPermissions.request,
    this.openSettings = MediaPermissions.openSettings,
    this.pickAnyFiles = _defaultPickAnyFiles,
  });

  final SharePickerTab initialTab;
  final Future<List<MediaItem>> Function() loadMedia;
  final Future<List<AndroidAppInfo>> Function() loadApps;
  final Future<Uint8List?> Function(MediaItem item) thumbnailLoader;

  /// Permission gate that runs before any media query — injectable so
  /// tests can simulate granted / denied / permanently-denied devices.
  final Future<MediaAccess> Function() requestMediaAccess;

  /// Deep link to the app's system settings page.
  final Future<bool> Function() openSettings;

  /// Opens the system document picker (SAF) for the "All files" tab and
  /// returns the chosen files as ready-to-stage [FileInfo]s.
  final Future<List<FileInfo>> Function() pickAnyFiles;

  /// Lazily fetches one app's launcher icon. Icons are deliberately not
  /// part of [loadApps] any more: rasterising hundreds of icons up front
  /// was what made the Apps tab feel slow.
  final Future<Uint8List?> Function(String packageName) appIconLoader;

  static Future<Uint8List?> _defaultThumbnail(MediaItem item) =>
      MediaLibrary.thumbnail(item.id, isVideo: item.isVideo);

  /// System document picker: any file type, multi-select. Picked URIs
  /// need no storage permission (Storage Access Framework).
  static Future<List<FileInfo>> _defaultPickAnyFiles() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return const [];
    return [
      for (final f in result.files)
        if (f.path != null)
          FileInfo(
            id: _uuid.v4(),
            fileName: f.name,
            size: f.size,
            fileType: fileTypeForName(f.name),
            localPath: f.path,
          ),
    ];
  }

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabs;
  final _searchController = TextEditingController();

  /// The query the lists are filtered by. Trails the text field by
  /// [_searchDebounceDelay] so the O(n) filter doesn't re-run — and both
  /// tabs don't rebuild — on every keystroke.
  String _query = '';
  Timer? _searchDebounce;
  static const _searchDebounceDelay = Duration(milliseconds: 200);
  final _thumbCache = <int, Future<Uint8List?>>{};
  final _iconCache = <String, Future<Uint8List?>>{};

  List<MediaItem>? _media;
  List<AndroidAppInfo>? _apps;
  bool _mediaFailed = false;
  bool _appsFailed = false;

  /// Media permission verdict; null while the first check is in flight.
  MediaAccess? _mediaAccess;

  /// Files picked via the system document picker, keyed by path.
  final _pickedFiles = <String, FileInfo>{};

  final _selectedMedia = <int, MediaItem>{};
  final _selectedApps = <String, AndroidAppInfo>{};
  final _selectedFiles = <String, FileInfo>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: switch (widget.initialTab) {
        SharePickerTab.photos => 0,
        SharePickerTab.apps => 1,
        SharePickerTab.files => 2,
      },
    );
    _load();
  }

  /// The user may grant the permission in system settings and come back
  /// — re-check on every resume so the grid fills in without a reopen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_mediaAccess == MediaAccess.denied ||
        _mediaAccess == MediaAccess.permanentlyDenied) {
      _gateAndLoadMedia();
    }
  }

  /// Photos and apps load independently so the faster tab paints as soon
  /// as its data arrives instead of waiting for the slower one.
  void _load() {
    _gateAndLoadMedia();
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

  /// Permission first, then the MediaStore query — querying without the
  /// grant silently returns zero rows, which is exactly the "empty grid,
  /// no prompt" bug this gate exists to prevent.
  void _gateAndLoadMedia() {
    unawaited(() async {
      final access = await widget.requestMediaAccess();
      if (!mounted) return;
      setState(() => _mediaAccess = access);
      // `unsupported` (desktop/iOS hosts) still queries: the injected
      // loader decides what, if anything, exists there.
      if (access == MediaAccess.denied ||
          access == MediaAccess.permanentlyDenied) {
        return;
      }
      try {
        final media = await widget.loadMedia();
        if (!mounted) return;
        setState(() => _media = media);
      } catch (_) {
        if (!mounted) return;
        setState(() => _mediaFailed = true);
      }
    }());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_searchDebounceDelay, () {
      if (!mounted || _query == text) return;
      setState(() => _query = text);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _query = '');
  }

  int get _selectedCount =>
      _selectedMedia.length + _selectedApps.length + _selectedFiles.length;

  int get _selectedBytes =>
      mediaTotalSize(_selectedMedia.values) +
      appsTotalSize(_selectedApps.values) +
      filesTotalSize(_selectedFiles.values);

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
      ..._selectedFiles.values,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query;
    final media = filterMedia(_media ?? const [], query);
    final apps = filterApps(_apps ?? const [], query);
    final files = filterFiles(_pickedFiles.values.toList(), query);
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
            Tab(icon: Icon(Icons.folder_outlined), text: 'All files'),
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
              onChanged: _onSearchChanged,
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
                        onPressed: _clearSearch,
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
                _filesTab(theme, files),
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
    if (_mediaAccess == MediaAccess.denied ||
        _mediaAccess == MediaAccess.permanentlyDenied) {
      return _permissionCard(theme);
    }
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
                // Decode at display size (tile is at most 110 lp wide):
                // cheaper decode, less GPU memory on a fast-scrolling grid.
                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth:
                      (110 * MediaQuery.devicePixelRatioOf(context)).round(),
                );
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

  /// Friendly inline explainer shown instead of the grid when media
  /// access is denied. Permanently-denied devices get the settings deep
  /// link — the one case where that's the expected UX.
  Widget _permissionCard(ThemeData theme) {
    final permanent = _mediaAccess == MediaAccess.permanentlyDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VSpace.x6),
        child: Container(
          key: const Key('media-permission-card'),
          padding: const EdgeInsets.all(VSpace.x6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: VRadius.mdAll,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 40,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: VSpace.x3),
              Text(
                'LanLink can\u2019t see your photos yet',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: VSpace.x2),
              Text(
                permanent
                    ? 'Media access is turned off for LanLink. Flip it '
                        'on in system settings and your photos and videos '
                        'will show up here.'
                    : 'Allow media access and your photos and videos '
                        'will show up here. Nothing leaves this device '
                        'unless you send it.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: VSpace.x4),
              if (permanent)
                FilledButton.icon(
                  key: const Key('media-open-settings'),
                  onPressed: widget.openSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open settings'),
                )
              else
                FilledButton.icon(
                  key: const Key('media-allow-access'),
                  onPressed: _gateAndLoadMedia,
                  icon: const Icon(Icons.lock_open_outlined),
                  label: const Text('Allow access'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ----- All files -----

  Future<void> _browseFiles() async {
    List<FileInfo> picked;
    try {
      picked = await widget.pickAnyFiles();
    } catch (_) {
      picked = const [];
    }
    if (!mounted || picked.isEmpty) return;
    setState(() {
      for (final file in picked) {
        final key = file.localPath ?? file.fileName;
        _pickedFiles[key] = file;
        _selectedFiles[key] = file; // picked ⇒ selected, one less tap
      }
    });
  }

  Widget _filesTab(ThemeData theme, List<FileInfo> files) {
    if (_pickedFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 44,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: VSpace.x3),
            Text(
              'Zips, PDFs, APKs \u2014 anything goes.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: VSpace.x4),
            FilledButton.tonalIcon(
              key: const Key('picker-browse-files'),
              onPressed: _browseFiles,
              icon: const Icon(Icons.folder_outlined),
              label: const Text('Browse files'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VSpace.x4),
          child: Row(
            children: [
              Text(
                '${files.length} file${files.length == 1 ? '' : 's'}',
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              TextButton.icon(
                key: const Key('picker-browse-more'),
                onPressed: _browseFiles,
                icon: const Icon(Icons.add),
                label: const Text('Add more'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
            itemCount: files.length,
            itemBuilder: (context, i) {
              final file = files[i];
              final key = file.localPath ?? file.fileName;
              final selected = _selectedFiles.containsKey(key);
              return CheckboxListTile(
                key: Key('file-$key'),
                value: selected,
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _selectedFiles[key] = file;
                  } else {
                    _selectedFiles.remove(key);
                  }
                }),
                secondary: const Icon(Icons.insert_drive_file_outlined),
                title: Text(file.fileName, overflow: TextOverflow.ellipsis),
                subtitle: Text(formatBytes(file.size)),
              );
            },
          ),
        ),
      ],
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
          secondary: _appIcon(context, theme, app),
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
  Widget _appIcon(BuildContext context, ThemeData theme, AndroidAppInfo app) {
    // Icons render at 40 lp — decode at that size instead of full raster.
    final iconCacheWidth =
        (40 * MediaQuery.devicePixelRatioOf(context)).round();
    final placeholder = CircleAvatar(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.android),
    );
    if (app.icon != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(app.icon!,
            width: 40, height: 40, cacheWidth: iconCacheWidth),
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
            child: Image.memory(bytes,
                width: 40, height: 40, cacheWidth: iconCacheWidth),
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
