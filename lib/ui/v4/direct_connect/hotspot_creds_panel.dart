import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Manual-join instructions shown under the QR while hosting a Direct
/// link. Android guests never need this (the scan auto-joins); everyone
/// else joins the network by hand, then scans. The hint adapts to the
/// host: a phone host expects iPhone/computer guests, a Windows PC host
/// expects phone guests.
class HotspotCredsPanel extends StatelessWidget {
  const HotspotCredsPanel({
    super.key,
    required this.ssid,
    required this.password,
  });

  final String ssid;
  final String password;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(VSpace.x4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: VRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            defaultTargetPlatform == TargetPlatform.windows
                ? "Phone won't scan? Join this Wi-Fi from it, then scan."
                : 'iPhone or computer? Join this Wi-Fi first, then scan.',
            style: VType.caption.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: VSpace.x3),
          _CredRow(label: 'Network', value: ssid),
          const SizedBox(height: VSpace.x2),
          _CredRow(label: 'Password', value: password),
        ],
      ),
    );
  }
}

class _CredRow extends StatelessWidget {
  const _CredRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: VType.label.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: VType.bodyStrong.copyWith(color: scheme.onSurface),
          ),
        ),
      ],
    );
  }
}
