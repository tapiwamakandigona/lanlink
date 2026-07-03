import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The v4 home surface: exactly two verbs — Send and Receive — plus a
/// visibility status line and an optional inline slot for a session strip.
///
/// Layout is responsive: verbs sit side by side when there is room
/// (>= 560px), stacked on narrow phones.
class TwoVerbHome extends StatelessWidget {
  const TwoVerbHome({
    super.key,
    required this.deviceName,
    required this.onSend,
    required this.onReceive,
    this.visible = true,
    this.sessionStrip,
  });

  /// This device's friendly name, e.g. "Purple-Otter".
  final String deviceName;

  /// Called when the Send verb is tapped.
  final VoidCallback onSend;

  /// Called when the Receive verb is tapped.
  final VoidCallback onReceive;

  /// Whether this device is currently discoverable on the network.
  final bool visible;

  /// Optional inline session strip (e.g. a compact [SessionCard]) shown
  /// under the verbs while a transfer is running.
  final Widget? sessionStrip;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 560;
        final verbs = [
          Expanded(
            child: _VerbCard(
              icon: Icons.north_east,
              label: 'Send',
              caption: 'Pick files, choose a device',
              primary: true,
              onTap: onSend,
            ),
          ),
          const SizedBox(width: VSpace.x4, height: VSpace.x4),
          Expanded(
            child: _VerbCard(
              icon: Icons.south_west,
              label: 'Receive',
              caption: 'Show a code, get files',
              primary: false,
              onTap: onReceive,
            ),
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (wide)
              SizedBox(height: 180, child: Row(children: verbs))
            else
              SizedBox(
                height: 300,
                child: Column(
                  children: [
                    Expanded(child: Row(children: [verbs[0]])),
                    const SizedBox(height: VSpace.x4),
                    Expanded(child: Row(children: [verbs[2]])),
                  ],
                ),
              ),
            const SizedBox(height: VSpace.x4),
            VisibilityStatusLine(deviceName: deviceName, visible: visible),
            if (sessionStrip != null) ...[
              const SizedBox(height: VSpace.x4),
              sessionStrip!,
            ],
          ],
        );
      },
    );
  }
}

/// The "You're visible as <name>" line under the home verbs.
class VisibilityStatusLine extends StatelessWidget {
  const VisibilityStatusLine({
    super.key,
    required this.deviceName,
    this.visible = true,
  });

  /// This device's friendly name, e.g. "Purple-Otter".
  final String deviceName;

  /// When false the line says the device is hidden.
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotColor = visible ? scheme.primary : scheme.outline;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: VSpace.x2),
        Flexible(
          child: Text.rich(
            TextSpan(
              style: VType.body.copyWith(color: scheme.onSurfaceVariant),
              children: visible
                  ? [
                      const TextSpan(text: "You're visible as "),
                      TextSpan(
                        text: deviceName,
                        style: VType.bodyStrong.copyWith(
                          fontSize: 15,
                          color: scheme.onSurface,
                        ),
                      ),
                    ]
                  : [const TextSpan(text: "You're hidden right now")],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _VerbCard extends StatelessWidget {
  const _VerbCard({
    required this.icon,
    required this.label,
    required this.caption,
    required this.primary,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String caption;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = primary ? scheme.primary : scheme.surfaceContainerLowest;
    final fg = primary ? scheme.onPrimary : scheme.onSurface;
    final sub =
        primary ? scheme.onPrimary.withOpacity(0.78) : scheme.onSurfaceVariant;
    return Material(
      color: bg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: VRadius.lgAll,
        side: primary
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(VSpace.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primary
                      ? scheme.onPrimary.withOpacity(0.16)
                      : scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    size: 22, color: primary ? fg : scheme.onPrimaryContainer),
              ),
              const Spacer(),
              Text(label, style: VType.heading.copyWith(color: fg)),
              const SizedBox(height: VSpace.x1),
              Text(
                caption,
                style: VType.caption.copyWith(color: sub),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
