import 'package:flutter/material.dart';

import '../../core/models/device.dart';
import '../../core/models/file_info.dart';
import '../../core/transfer/receiver.dart';
import '../../core/util/friendly_files.dart';

/// Simple-mode incoming-transfer prompt.
///
/// Replaces the technical receive dialog with plain language and two huge
/// buttons: "<Device> wants to send you 3 photos" → "Yes, save them" /
/// "No, thanks". No IP addresses, no fingerprints, no checkboxes — one
/// decision per screen.
Future<({AcceptDecision decision, bool trust})> showSimpleReceivePrompt({
  required BuildContext context,
  required Device peer,
  required List<FileInfo> files,
  String? nickname,
}) async {
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => _SimpleReceiveSheet(
      peerName: _displayName(nickname, peer),
      files: files,
    ),
  );
  if (accepted == true) {
    return (
      decision: AcceptDecision.accept(files.map((f) => f.id).toSet()),
      trust: false,
    );
  }
  return (decision: AcceptDecision.reject(), trust: false);
}

String _displayName(String? nickname, Device peer) {
  final nick = nickname?.trim();
  if (nick != null && nick.isNotEmpty) return nick;
  return peer.alias.trim().isEmpty ? 'Another device' : peer.alias.trim();
}

class _SimpleReceiveSheet extends StatelessWidget {
  const _SimpleReceiveSheet({required this.peerName, required this.files});

  final String peerName;
  final List<FileInfo> files;

  IconData get _icon {
    final hasMedia =
        files.any((f) => f.fileType == 'image' || f.fileType == 'video');
    return hasMedia ? Icons.photo_library_outlined : Icons.folder_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: scheme.primaryContainer,
              child: Icon(_icon, size: 44, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 18),
            Text(
              peerName,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'wants to send you',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Text(
              describeFilesFriendly(files),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2C9A4B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  textStyle: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes, save them'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: scheme.error,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: theme.textTheme.titleMedium,
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No, thanks'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
