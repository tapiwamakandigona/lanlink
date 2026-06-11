import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/session.dart';
import '../../core/util/friendly_files.dart';

/// Full-screen "All saved!" confirmation shown in Simple mode after an
/// incoming transfer completes. Addresses the #1 moment of doubt for
/// non-technical users: "did it work, and where did my photos go?"
class SimpleSavedPage extends StatelessWidget {
  const SimpleSavedPage({
    super.key,
    required this.session,
    this.peerDisplayName,
  });

  final TransferSession session;
  final String? peerDisplayName;

  String get _peerName {
    final nick = peerDisplayName?.trim();
    if (nick != null && nick.isNotEmpty) return nick;
    final alias = session.peer.alias.trim();
    return alias.isEmpty ? 'the other device' : alias;
  }

  /// Directory the files landed in, for the desktop "Open the folder"
  /// button. Null on Android (files are republished into Downloads/LanLink
  /// via MediaStore, which has no openable filesystem path).
  String? get _savedDir {
    if (Platform.isAndroid) return null;
    for (final fp in session.files.values) {
      final path = fp.savedPath;
      if (path != null && path.isNotEmpty) return p.dirname(path);
    }
    return null;
  }

  String get _whereText {
    if (Platform.isAndroid) {
      return 'in your Downloads, in the LanLink folder';
    }
    final dir = _savedDir;
    if (dir == null) return 'on this device';
    return 'in your ${p.basename(dir)} folder';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final received =
        session.files.values.map((fp) => fp.file).toList(growable: false);
    final dir = _savedDir;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2C9A4B),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 72, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'All saved!',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${describeFilesFriendly(received)} from $_peerName\n'
                    'are $_whereText.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (dir != null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          textStyle: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: () => _openFolder(context, dir),
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Open the folder'),
                      ),
                    ),
                  if (dir != null) const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: theme.textTheme.titleMedium,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openFolder(BuildContext context, String dir) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launchUrl(Uri.directory(dir));
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text('Your files are in: $dir')),
      );
    }
  }
}
