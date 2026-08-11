import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Manual-join instructions shown under the QR while hosting a Direct
/// link. Android guests never need this (the scan auto-joins); everyone
/// else joins the network by hand, then scans. The hint adapts to the
/// host: a phone host expects iPhone/computer guests, a Windows PC host
/// expects phone guests.
class HotspotCredsPanel extends StatefulWidget {
  const HotspotCredsPanel({
    super.key,
    required this.ssid,
    required this.password,
  });

  final String ssid;
  final String password;

  @override
  State<HotspotCredsPanel> createState() => _HotspotCredsPanelState();
}

class _HotspotCredsPanelState extends State<HotspotCredsPanel> {
  /// Inline copy feedback, matching the guest-side [JoinFallbackSheet]:
  /// a SnackBar could render behind whatever surface hosts this panel,
  /// where the user can't see it.
  bool _copied = false;
  Timer? _copiedReset;

  @override
  void dispose() {
    _copiedReset?.cancel();
    super.dispose();
  }

  Future<void> _copyPassword() async {
    await Clipboard.setData(ClipboardData(text: widget.password));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedReset?.cancel();
    _copiedReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

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
          _CredRow(label: 'Network', value: widget.ssid),
          const SizedBox(height: VSpace.x2),
          _CredRow(
            label: 'Password',
            value: widget.password,
            // Manual joiners type this into another device, so give them
            // the same copy affordance the guest fallback sheet has.
            trailing: _copied
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: VSpace.x1),
                      Text(
                        'Copied',
                        style: VType.label.copyWith(color: scheme.primary),
                      ),
                    ],
                  )
                : IconButton(
                    tooltip: 'Copy password',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: _copyPassword,
                  ),
          ),
        ],
      ),
    );
  }
}

class _CredRow extends StatelessWidget {
  const _CredRow({required this.label, required this.value, this.trailing});

  final String label;
  final String value;

  /// Optional trailing affordance (copy button / "Copied" confirmation).
  final Widget? trailing;

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
        if (trailing != null) trailing!,
      ],
    );
  }
}
