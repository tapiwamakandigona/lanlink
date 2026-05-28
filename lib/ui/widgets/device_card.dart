import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/device.dart';
import '../../core/protocol/constants.dart';
import '../../state/app_state.dart';

/// A small, tappable summary of a LAN peer.
///
/// Shows the persisted nickname (if any) instead of the alias announced by
/// the peer, and supports a long-press gesture for the peer action sheet
/// (rename, history, trust toggle).
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    this.selected = false,
  });

  final Device device;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Optional override for the trailing icon (e.g. a checkbox in
  /// multi-select mode). Defaults to a send arrow.
  final Widget? trailing;

  /// When true, the card paints with a selected background. Used for
  /// fan-out send (pick multiple peers, send to all at once).
  final bool selected;

  IconData get _icon {
    switch (device.deviceType) {
      case LanLinkProtocol.deviceTypeMobile:
        return Icons.phone_android;
      case LanLinkProtocol.deviceTypeDesktop:
        return Icons.computer;
      default:
        return Icons.devices_other;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<AppState>().settings;
    final nickname = settings.nicknameFor(device.fingerprint);
    final isTrusted =
        settings.trustedFingerprints.contains(device.fingerprint) &&
            device.fingerprint.isNotEmpty;
    final displayName = nickname?.isNotEmpty == true
        ? nickname!
        : (device.alias.isEmpty ? 'Unknown' : device.alias);
    return Card(
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                child: Icon(_icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isTrusted) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified_user,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (nickname != null && device.alias.isNotEmpty)
                          device.alias,
                        if (device.deviceModel.isNotEmpty) device.deviceModel,
                        '${device.ip}:${device.port}',
                      ].join(' • '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              trailing ?? const Icon(Icons.send_outlined),
            ],
          ),
        ),
      ),
    );
  }
}
