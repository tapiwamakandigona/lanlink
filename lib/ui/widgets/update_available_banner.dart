import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update/update_checker.dart';

/// Slim banner that surfaces a newer LanLink release. Tapping it opens a
/// modal with release notes and a "Download" button that drops straight to
/// the matching binary for the current platform (APK on Android, ZIP on
/// Windows) — never the source-code links.
///
/// The banner is fully dismissible: the user can hit the close icon to skip
/// the current release (it won't reappear until a newer one ships) or pick
/// "Later" from the details sheet. Updates are never forced.
class UpdateAvailableBanner extends StatelessWidget {
  const UpdateAvailableBanner({
    super.key,
    required this.release,
    this.onDismiss,
  });

  final ReleaseInfo release;

  /// Called when the user explicitly dismisses the banner via the close
  /// icon or the "Skip this version" button in the details sheet. Hosts
  /// typically persist the tag so the banner doesn't reappear for it.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showDetails(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              children: [
                Icon(
                  Icons.system_update_alt,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LanLink ${release.tagName} is available',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Tap to see what\'s new. Updates are optional.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    tooltip: 'Skip this version',
                    icon: Icon(
                      Icons.close,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    onPressed: onDismiss,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.chevron_right,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDetails(BuildContext context) async {
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
                  'Update to ${release.tagName}',
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
                    if (onDismiss != null)
                      TextButton(
                        onPressed: () {
                          onDismiss!();
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
}
