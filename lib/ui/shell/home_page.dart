import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/file_info.dart';
import '../../core/platform/incoming_share.dart';
import '../../state/app_state.dart';
import '../v4/v4.dart';
import '../widgets/connected_peer_card.dart';
import '../widgets/desktop_drop_region.dart';
import '../widgets/live_session_card.dart';
import '../widgets/update_available_banner.dart';
import 'send_page.dart';
import 'session_display.dart';

/// The one home screen: two verbs (Receive / Send) on top, the visible
/// sessions below, grouped by groupId so an "+ Add files" exchange with a
/// peer reads as a single unit.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    // Android "share to LanLink": files shared from another app land here;
    // consume them and jump straight into the send flow with them staged.
    IncomingShare.onShareReceived(_consumePendingShares);
    unawaited(_consumePendingShares());
  }

  Future<void> _consumePendingShares() async {
    final List<FileInfo> shares;
    try {
      shares = await IncomingShare.consume();
    } catch (_) {
      return;
    }
    if (shares.isEmpty || !mounted) return;
    unawaited(Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SendPage(prestagedFiles: shares),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final visible = state.visibleSessions;
    final clusters = clusterSessions(visible);
    final hasFinished = visible.any((s) => s.isTerminal);
    final update = state.updateChecker.availableUpdate;

    return DesktopDropRegion(
      onFiles: (files) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SendPage(prestagedFiles: files),
      )),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('LanLink'),
          actions: [
            IconButton(
              tooltip: 'History',
              icon: const Icon(Icons.history),
              onPressed: () => Navigator.of(context).pushNamed('/history'),
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).pushNamed('/settings'),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (route) => Navigator.of(context).pushNamed(route),
              itemBuilder: (context) => const [
                PopupMenuItem(value: '/help', child: Text('Help')),
                PopupMenuItem(value: '/about', child: Text('About')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(VSpace.x4),
                children: [
                  if (update != null &&
                      state.settings.skippedUpdateVersion != update.tagName)
                    UpdateAvailableBanner(
                      release: update,
                      onDismiss: () => state.settings
                          .setSkippedUpdateVersion(update.tagName),
                    ),
                  TwoVerbHome(
                    deviceName: state.displayAlias,
                    visible: state.port != null,
                    onRetryVisibility: () => state.retryReceiver(),
                    onSend: () => Navigator.of(context).pushNamed('/send'),
                    onReceive: () =>
                        Navigator.of(context).pushNamed('/receive'),
                  ),
                  // Symmetric sessions (F3): every linked peer gets a strip
                  // with "Send files" (no re-scan needed) and Disconnect.
                  if (state.linkedPeers.isNotEmpty) ...[
                    const SizedBox(height: VSpace.x6),
                    for (final peer in state.linkedPeers) ...[
                      ConnectedPeerCard(
                        peerName: displayPeerName(state.settings, peer),
                        verified: state.settings.isPinned(peer.fingerprint),
                        onSendFiles: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SendPage(targetPeer: peer),
                          ),
                        ),
                        onDisconnect: () =>
                            unawaited(state.disconnectPeer(peer)),
                      ),
                      const SizedBox(height: VSpace.x3),
                    ],
                  ],
                  if (clusters.isNotEmpty) ...[
                    const SizedBox(height: VSpace.x6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Transfers',
                            style:
                                VType.heading.copyWith(color: scheme.onSurface),
                          ),
                        ),
                        if (hasFinished)
                          TextButton(
                            onPressed: state.dismissFinishedSessions,
                            child: const Text('Clear finished'),
                          ),
                      ],
                    ),
                    const SizedBox(height: VSpace.x2),
                    for (final cluster in clusters) ...[
                      _ClusterView(cluster: cluster, state: state),
                      const SizedBox(height: VSpace.x3),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders one [SessionCluster]: a lone card, or a bordered stack with a
/// group header when several sessions share a groupId.
class _ClusterView extends StatelessWidget {
  const _ClusterView({required this.cluster, required this.state});

  final SessionCluster cluster;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (cluster.sessions.length == 1) {
      return LiveSessionCard(
        session: cluster.sessions.first,
        state: state,
      );
    }
    final peer = cluster.sessions.first.peer;
    return Container(
      decoration: BoxDecoration(
        borderRadius: VRadius.lgAll,
        border: Border.all(color: scheme.outlineVariant),
        color: scheme.surfaceContainerLow,
      ),
      padding: const EdgeInsets.all(VSpace.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                VSpace.x2, VSpace.x1, VSpace.x2, VSpace.x3),
            child: Text(
              'To ${displayPeerName(state.settings, peer)} · '
              '${cluster.sessions.length} transfers',
              style: VType.label.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final (i, s) in cluster.sessions.indexed) ...[
            if (i > 0) const SizedBox(height: VSpace.x2),
            LiveSessionCard(session: s, state: state),
          ],
        ],
      ),
    );
  }

  // Each card subscribes to its own TransferSession inside LiveSessionCard,
  // so 10 Hz progress ticks repaint one card — not this whole page.
}
