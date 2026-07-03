import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform/app_invite.dart';

/// A small "Invite a friend" tile for the settings page.
///
/// Android-only: tapping it opens the system share sheet with the LanLink
/// APK attached so the user can beam it over Bluetooth or Quick Share.
/// On split-APK installs (where the base split alone wouldn't install)
/// it falls back to offering the universal-download link. Renders
/// nothing at all on iOS/desktop.
class InviteFriendTile extends StatelessWidget {
  const InviteFriendTile({super.key, this.version});

  /// Version string stamped into the shared file name (e.g. `4.1.0`).
  final String? version;

  @override
  Widget build(BuildContext context) {
    if (!AppInvite.isSupported) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(
          Icons.bluetooth_outlined,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Invite a friend'),
        subtitle: Text(
          'Send them the LanLink app over Bluetooth or Quick Share. '
          'They\'ll need to allow "install unknown apps" once.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.ios_share, size: 18),
        onTap: () => _invite(context),
      ),
    );
  }

  Future<void> _invite(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await AppInvite.shareApk(version: version ?? 'latest');
    if (!context.mounted) return;
    switch (outcome) {
      case AppInviteOutcome.shared:
        break; // System sheet is on screen; nothing more to say.
      case AppInviteOutcome.needsDownloadLink:
        await _showDownloadLinkDialog(context);
      case AppInviteOutcome.unavailable:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Couldn\'t share the app right now.'),
          ),
        );
    }
  }

  Future<void> _showDownloadLinkDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Share a download link instead'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This install came in several pieces, so the app file '
                'itself can\'t be beamed directly. Send your friend the '
                'download link instead:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              SelectableText(
                AppInvite.downloadUrl,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy link'),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                await Clipboard.setData(
                  const ClipboardData(text: AppInvite.downloadUrl),
                );
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Link copied')),
                );
              },
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.share, size: 18),
              label: const Text('Share link'),
              onPressed: () async {
                final navigator = Navigator.of(context);
                await AppInvite.shareDownloadLink();
                navigator.pop();
              },
            ),
          ],
        );
      },
    );
  }
}
