import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/wifi_joiner.dart';
import '../theme/tokens.dart';

/// What the user picked on the [JoinFallbackSheet].
enum JoinFallbackAction {
  /// Tier 2: open the system "Add networks" save panel (API 30+).
  addNetwork,

  /// Tier 3: open Wi-Fi settings and join by hand.
  openSettings,
}

/// Bottom sheet shown when the programmatic (Tier-1) hotspot join fails:
/// explains what happened and offers the Tier-2 "save it for me" panel
/// (when the platform has it) and the manual Wi-Fi-settings route, with
/// the password shown big for typing plus a copy button. Pops with the
/// chosen [JoinFallbackAction], or null on cancel/dismiss.
class JoinFallbackSheet extends StatelessWidget {
  const JoinFallbackSheet({
    super.key,
    required this.ssid,
    required this.password,
    required this.canAddNetwork,
    this.reason,
  });

  final String ssid;
  final String password;

  /// Whether the Tier-2 "Add network for me" panel exists on this device.
  final bool canAddNetwork;

  /// Why Tier 1 failed, for honest wording. Null falls back to a generic
  /// explanation.
  final WifiJoinResult? reason;

  String get _explanation => switch (reason) {
        WifiJoinResult.timeout =>
          'The Android connection dialog timed out before the network was '
              'joined.',
        WifiJoinResult.declinedOrUnavailable =>
          "Android couldn't find the network, or the connection dialog was "
              'dismissed.',
        _ => "This phone couldn't join the network automatically.",
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      // Scrollable so the tall password + three actions never overflow on
      // small screens / split-screen windows.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            VSpace.x6, VSpace.x5, VSpace.x6, VSpace.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Couldn\'t join "$ssid" automatically',
              style: VType.heading.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: VSpace.x2),
            Text(
              '$_explanation You can still connect — pick an option below, '
              'then come back to LanLink.',
              style: VType.body.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: VSpace.x5),
            Container(
              padding: const EdgeInsets.all(VSpace.x4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: VRadius.mdAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Network',
                    style: VType.label.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    ssid,
                    style: VType.bodyStrong.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: VSpace.x3),
                  Text(
                    'Password',
                    style: VType.label.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          password,
                          style:
                              VType.display.copyWith(color: scheme.onSurface),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy password',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: password));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Password copied')),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: VSpace.x5),
            if (canAddNetwork) ...[
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(JoinFallbackAction.addNetwork),
                icon: const Icon(Icons.wifi_find_rounded),
                label: const Text('Add network for me'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: VSpace.x3),
            ],
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(JoinFallbackAction.openSettings),
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Open Wi-Fi settings'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: VSpace.x2),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
