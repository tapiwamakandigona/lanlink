import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/device.dart';
import '../../core/models/file_info.dart';
import '../../core/models/session.dart';
import '../../core/protocol/constants.dart';
import '../../core/util/friendly_files.dart';
import '../../state/app_state.dart';

/// Simple-mode "who should get these files?" page. Big device tiles,
/// plain names, no IPs or fingerprints. Discovery refreshes automatically
/// while the page is open.
class SimpleDevicePickerPage extends StatefulWidget {
  const SimpleDevicePickerPage({super.key, required this.files});

  final List<FileInfo> files;

  @override
  State<SimpleDevicePickerPage> createState() => _SimpleDevicePickerPageState();
}

class _SimpleDevicePickerPageState extends State<SimpleDevicePickerPage> {
  Timer? _rescan;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    unawaited(state.refreshDiscovery());
    // Keep looking while the page is open so the other device pops in as
    // soon as it's reachable — no manual refresh button needed.
    _rescan = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      unawaited(context.read<AppState>().refreshDiscovery());
    });
  }

  @override
  void dispose() {
    _rescan?.cancel();
    super.dispose();
  }

  Future<void> _sendTo(Device peer) async {
    final state = context.read<AppState>();
    final navigator = Navigator.of(context);
    final session = await state.sendFiles(peer: peer, files: widget.files);
    if (!mounted) return;
    final name = state.settings.nicknameFor(peer.fingerprint) ??
        (peer.alias.trim().isEmpty ? 'the other device' : peer.alias.trim());
    unawaited(navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => SimpleSendProgressPage(
          session: session,
          peerDisplayName: name,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = context.watch<AppState>();
    final peers = state.peers.values.toList()
      ..sort((a, b) => a.alias.toLowerCase().compareTo(b.alias.toLowerCase()));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send to…'),
        titleTextStyle: theme.textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Sending ${describeFilesFriendly(widget.files)}.\n'
                    'Tap the device that should get them:',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: peers.isEmpty
                        ? _buildSearching(theme, scheme)
                        : ListView.separated(
                            itemCount: peers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, i) =>
                                _buildPeerTile(theme, scheme, state, peers[i]),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearching(ThemeData theme, ColorScheme scheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(strokeWidth: 5),
        ),
        const SizedBox(height: 24),
        Text(
          'Looking for nearby devices…',
          textAlign: TextAlign.center,
          style:
              theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          'Make sure LanLink is open on the other device\n'
          'and both are on the same Wi-Fi.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildPeerTile(
    ThemeData theme,
    ColorScheme scheme,
    AppState state,
    Device peer,
  ) {
    final name = state.settings.nicknameFor(peer.fingerprint) ??
        (peer.alias.trim().isEmpty ? 'Unnamed device' : peer.alias.trim());
    final icon = peer.deviceType == LanLinkProtocol.deviceTypeMobile
        ? Icons.smartphone
        : Icons.computer;
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _sendTo(peer),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.primary, width: 2),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, size: 30, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.chevron_right, size: 32, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple-mode sending screen: one giant progress bar, then an in-place
/// "Sent!" confirmation (or a friendly, jargon-free error).
class SimpleSendProgressPage extends StatelessWidget {
  const SimpleSendProgressPage({
    super.key,
    required this.session,
    required this.peerDisplayName,
  });

  final TransferSession session;
  final String peerDisplayName;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Don't let a stray back-gesture abandon the progress view mid-send;
      // terminal states re-enable it.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (session.status != TransferStatus.transferring &&
            session.status != TransferStatus.awaitingAccept) {
          Navigator.of(context).popUntil((r) => r.isFirst);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: AnimatedBuilder(
            animation: session,
            builder: (context, _) {
              switch (session.status) {
                case TransferStatus.awaitingAccept:
                  return _Waiting(peerName: peerDisplayName);
                case TransferStatus.transferring:
                  return _Sending(session: session, peerName: peerDisplayName);
                case TransferStatus.completed:
                  return _Sent(session: session, peerName: peerDisplayName);
                case TransferStatus.failed:
                case TransferStatus.cancelled:
                  return _Failed(peerName: peerDisplayName);
              }
            },
          ),
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.peerName});

  final String peerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Centered(
      children: [
        const Center(
          child: SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(strokeWidth: 5),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Waiting for $peerName…',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          'They just need to tap "Yes" on their screen.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Sending extends StatelessWidget {
  const _Sending({required this.session, required this.peerName});

  final TransferSession session;
  final String peerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final files = session.files.values.map((fp) => fp.file).toList();
    final pct = (session.fraction * 100).clamp(0, 100).round();
    return _Centered(
      children: [
        Text(
          'Sending ${describeFilesFriendly(files)}\nto $peerName…',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700, height: 1.35),
        ),
        const SizedBox(height: 32),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LinearProgressIndicator(
            value: session.fraction.clamp(0.0, 1.0),
            minHeight: 18,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '$pct%',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _Sent extends StatelessWidget {
  const _Sent({required this.session, required this.peerName});

  final TransferSession session;
  final String peerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final files = session.files.values.map((fp) => fp.file).toList();
    return _Centered(
      children: [
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: const BoxDecoration(
              color: Color(0xFF2C9A4B),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.check_rounded, size: 72, color: Colors.white),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Sent!',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          '$peerName now has your ${describeFilesFriendly(files)}.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 32),
        FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
            textStyle: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.peerName});

  final String peerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Centered(
      children: [
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.close_rounded,
                size: 72, color: scheme.onErrorContainer),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "That didn't work",
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          'The files did not reach $peerName.\n'
          'Check that both devices are on the same Wi-Fi,\n'
          'then try again.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 32),
        FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
            textStyle: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
          child: const Text('Back to start'),
        ),
      ],
    );
  }
}
