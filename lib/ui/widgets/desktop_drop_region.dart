import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/file_info.dart';
import '../../core/util/dropped_paths.dart';
import '../v4/v4.dart';

/// Desktop-only drag-and-drop region: wraps [child] in a [DropTarget] on
/// Windows / macOS / Linux and calls [onFiles] with the staged [FileInfo]s
/// when the user drops files or folders onto the window. On mobile (no OS
/// drag-and-drop concept for app windows) it renders [child] untouched.
///
/// While a drag hovers over the window a dimmed overlay with [hint] makes
/// the drop affordance obvious.
class DesktopDropRegion extends StatefulWidget {
  const DesktopDropRegion({
    super.key,
    required this.child,
    required this.onFiles,
    this.hint = 'Drop to send',
  });

  final Widget child;
  final void Function(List<FileInfo> files) onFiles;
  final String hint;

  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  State<DesktopDropRegion> createState() => _DesktopDropRegionState();
}

class _DesktopDropRegionState extends State<DesktopDropRegion> {
  bool _hovering = false;

  Future<void> _handleDrop(DropDoneDetails details) async {
    final paths = [
      for (final f in details.files)
        if (f.path.isNotEmpty) f.path,
    ];
    if (paths.isEmpty) return;
    final files = await fileInfosForDroppedPaths(paths);
    if (files.isEmpty || !mounted) return;
    widget.onFiles(files);
  }

  @override
  Widget build(BuildContext context) {
    if (!DesktopDropRegion.isSupported) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return DropTarget(
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: (details) {
        setState(() => _hovering = false);
        unawaited(_handleDrop(details));
      },
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_hovering)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: scheme.surface.withOpacity(0.85),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: VSpace.x6, vertical: VSpace.x4),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: VRadius.lgAll,
                      border: Border.all(color: scheme.primary, width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download_rounded,
                            size: 40, color: scheme.onPrimaryContainer),
                        const SizedBox(height: VSpace.x2),
                        Text(
                          widget.hint,
                          style: VType.heading
                              .copyWith(color: scheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
