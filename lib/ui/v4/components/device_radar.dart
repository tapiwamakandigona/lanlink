import 'package:flutter/material.dart';

import '../models.dart';
import '../theme/tokens.dart';
import 'verified_badge.dart';

/// Named device bubbles for nearby peers. Shows initials, name, a
/// device-type icon, and an optional Verified badge — never an address.
///
/// Renders as a wrapping grid of [DeviceBubble]s; shows a calm searching
/// state when [peers] is empty.
class DeviceRadar extends StatelessWidget {
  const DeviceRadar({
    super.key,
    required this.peers,
    required this.onPeerTap,
    this.searching = true,
  });

  /// The nearby peers to render, in display order.
  final List<RadarPeerData> peers;

  /// Called with the tapped peer.
  final ValueChanged<RadarPeerData> onPeerTap;

  /// When true and [peers] is empty, shows the "Looking around…" state.
  final bool searching;

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) return _EmptyRadar(searching: searching);
    return Wrap(
      spacing: VSpace.x4,
      runSpacing: VSpace.x5,
      children: [
        for (final peer in peers)
          DeviceBubble(peer: peer, onTap: () => onPeerTap(peer)),
      ],
    );
  }
}

/// One tappable peer on the radar: initials disc + type icon + name +
/// optional compact Verified badge.
class DeviceBubble extends StatelessWidget {
  const DeviceBubble({super.key, required this.peer, required this.onTap});

  /// What to render.
  final RadarPeerData peer;

  /// Fired on tap.
  final VoidCallback onTap;

  static const _typeIcons = <DeviceType, IconData>{
    DeviceType.phone: Icons.smartphone,
    DeviceType.tablet: Icons.tablet_mac,
    DeviceType.laptop: Icons.laptop_mac,
    DeviceType.desktop: Icons.desktop_windows,
  };

  /// "Purple-Otter" -> "PO"; single words use the first two letters.
  static String initialsFor(String name) {
    final parts =
        name.split(RegExp(r'[\s\-_]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final w = parts.first;
      return w.length >= 2 ? w.substring(0, 2).toUpperCase() : w.toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 92,
      child: Semantics(
        button: true,
        label: peer.verified ? '${peer.name}, verified' : peer.name,
        child: InkWell(
          onTap: onTap,
          borderRadius: VRadius.mdAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: VSpace.x2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initialsFor(peer.name),
                        style: VType.bodyStrong.copyWith(
                          color: scheme.onSecondaryContainer,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLowest,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Icon(
                          _typeIcons[peer.deviceType],
                          size: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (peer.verified)
                      const Positioned(
                        right: -2,
                        top: -2,
                        child: VerifiedBadge(compact: true),
                      ),
                  ],
                ),
                const SizedBox(height: VSpace.x2),
                Text(
                  peer.name,
                  style: VType.label
                      .copyWith(color: scheme.onSurface, height: 1.2),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRadar extends StatelessWidget {
  const _EmptyRadar({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          vertical: VSpace.x8, horizontal: VSpace.x6),
      decoration: BoxDecoration(
        borderRadius: VRadius.mdAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          if (searching)
            // The indeterminate spinner repaints every frame; the boundary
            // keeps that repaint from spilling into the rest of the card.
            RepaintBoundary(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: scheme.primary,
                ),
              ),
            )
          else
            Icon(Icons.wifi_tethering_off,
                size: 24, color: scheme.onSurfaceVariant),
          const SizedBox(height: VSpace.x3),
          Text(
            searching ? 'Looking around…' : 'No devices found yet',
            style: VType.bodyStrong.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: VSpace.x1),
          Text(
            searching
                ? 'Devices on your network will appear here.'
                // Passive discovery keeps listening even when no sweep is
                // in flight — this state is "not found yet", not "gave
                // up". Say what actually unblocks people.
                : 'Make sure both devices are on the same Wi-Fi and the '
                    'other device has LanLink open — or scan their code '
                    'below.',
            style: VType.caption.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
