import 'package:flutter/material.dart';

import '../../core/models/device.dart';
import '../../core/protocol/constants.dart';

/// A small, tappable summary of a LAN peer.
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.onTap,
  });

  final Device device;
  final VoidCallback onTap;

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
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
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
                    Text(
                      device.alias.isEmpty ? 'Unknown' : device.alias,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
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
              const Icon(Icons.send_outlined),
            ],
          ),
        ),
      ),
    );
  }
}
