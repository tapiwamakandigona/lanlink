import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update/update_checker.dart';
import '../../state/app_state.dart';

/// A self-contained "Check for updates" list tile that:
///
/// * Shows the current app version and the last-checked time.
/// * Lets the user trigger a manual poll of the release manifest.
/// * Surfaces the latest release in a modal sheet so the user can read the
///   notes and download the binary for their platform — **never** linking
///   to the source code.
/// * Lets the user clear a previously skipped version so the home-screen
///   banner reappears.
///
/// Updates are always optional: this widget never forces a download or
/// blocks the UI on a release being installed.
class CheckForUpdatesTile extends StatelessWidget {
  const CheckForUpdatesTile({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final checker = state.updateChecker;
    final current = checker.currentVersion?.toString() ?? '—';
    final lastChecked = checker.lastCheckedAt;
    final lastCheckedText = lastChecked == null
        ? 'Not checked yet'
        : 'Last checked ${_formatRelative(lastChecked)}';
    final hasUpdate = checker.availableUpdate != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              hasUpdate ? Icons.system_update_alt : Icons.cloud_done_outlined,
              color: hasUpdate
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(
              hasUpdate
                  ? 'Update available: ${checker.availableUpdate!.tagName}'
                  : 'You\'re on the latest version',
            ),
            subtitle: Text('Installed: $current  •  $lastCheckedText'),
            trailing: checker.isChecking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'Check now',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _check(context),
                  ),
            onTap: checker.isChecking ? null : () => _check(context),
          ),
          if (hasUpdate) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Updates are optional. You can skip a version or grab it later.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showDetails(
                      context,
                      checker.availableUpdate!,
                    ),
                    child: const Text('View'),
                  ),
                ],
              ),
            ),
          ],
          if (state.settings.skippedUpdateVersion != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'You skipped ${state.settings.skippedUpdateVersion}.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        state.settings.setSkippedUpdateVersion(null),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _check(BuildContext context) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    await state.updateChecker.checkNow();
    if (!context.mounted) return;
    final update = state.updateChecker.availableUpdate;
    if (update == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('You\'re on the latest version')),
      );
    } else {
      await _showDetails(context, update);
    }
  }

  Future<void> _showDetails(BuildContext context, ReleaseInfo release) async {
    final state = context.read<AppState>();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final downloadUrl = release.downloadUrlForCurrentPlatform;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, controller) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LanLink ${release.tagName}',
                  style: theme.textTheme.titleLarge,
                ),
                if (release.isPrerelease)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Pre-release',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    controller: controller,
                    child: Text(
                      release.body.isEmpty
                          ? 'No release notes provided.'
                          : release.body,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () {
                        state.settings.setSkippedUpdateVersion(release.tagName);
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('Skip this version'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Later'),
                    ),
                    FilledButton.icon(
                      onPressed: downloadUrl == null
                          ? null
                          : () => _launch(sheetContext, downloadUrl),
                      icon: const Icon(Icons.download),
                      label: Text(
                        downloadUrl == null
                            ? 'No build for this platform'
                            : 'Download',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  static String _formatRelative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
  }
}
