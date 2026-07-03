import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// How the receiver expects the sender to reach it.
enum NetworkMode {
  /// Both devices share a Wi-Fi network (today's default flow).
  sameWifi,

  /// No shared network — this device hosts a direct link hotspot.
  directLink,
}

/// Ember-styled two-option segmented switch: "Same Wi-Fi" vs
/// "No shared Wi-Fi". One tap flips the receive surface between the
/// LAN QR flow and Direct link hosting — deliberately not a wizard.
class NetworkModeSwitch extends StatelessWidget {
  const NetworkModeSwitch({
    super.key,
    required this.mode,
    required this.onChanged,
    this.enabled = true,
  });

  final NetworkMode mode;
  final ValueChanged<NetworkMode> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(VSpace.x1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: VRadius.smAll,
      ),
      child: Row(
        children: [
          _Segment(
            label: 'Same Wi-Fi',
            selected: mode == NetworkMode.sameWifi,
            enabled: enabled,
            onTap: () => onChanged(NetworkMode.sameWifi),
          ),
          _Segment(
            label: 'No shared Wi-Fi',
            selected: mode == NetworkMode.directLink,
            enabled: enabled,
            onTap: () => onChanged(NetworkMode.directLink),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: enabled && !selected ? onTap : null,
          child: AnimatedContainer(
            duration: VMotion.base,
            curve: VMotion.ease,
            padding: const EdgeInsets.symmetric(
              vertical: VSpace.x2 + 2,
              horizontal: VSpace.x2,
            ),
            decoration: BoxDecoration(
              color: selected ? scheme.surface : Colors.transparent,
              borderRadius: const BorderRadius.all(
                Radius.circular(VRadius.sm - 2),
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: scheme.shadow.withOpacity(0.10),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : const [],
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VType.label.copyWith(
                color: selected
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant.withOpacity(enabled ? 1.0 : 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
