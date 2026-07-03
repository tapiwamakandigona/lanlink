import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../core/discovery/connect_payload.dart';
import '../../../core/models/device.dart';
import '../../../core/platform/wifi_joiner.dart';
import 'host_hotspot_page.dart';
import '../../../core/protocol/constants.dart';
import '../../../state/app_state.dart';
import 'simple_session_page.dart';

/// Simple-mode Send: connect first, pick files later.
///
/// One screen, two paths to the same place:
/// * a live camera viewfinder on top — scan the receiver's QR
///   (works even off-network: hotspot QRs are joined automatically);
/// * a nearby-devices list below — same Wi-Fi receivers usually appear
///   here before anyone bothers scanning.
///
/// Both paths land on [SimpleSessionPage].
class SendConnectPage extends StatefulWidget {
  const SendConnectPage({
    super.key,
    this.pcMode = false,
    this.scannerBuilder,
  });

  /// "Connect to a computer" entry point: identical mechanics, hint copy
  /// tuned to the PC-shows-the-QR flow.
  final bool pcMode;

  /// Test hook: replaces the camera viewfinder widget.
  final Widget Function(BuildContext, void Function(String raw))?
      scannerBuilder;

  static bool get cameraSupported => Platform.isAndroid || Platform.isIOS;

  @override
  State<SendConnectPage> createState() => _SendConnectPageState();
}

class _SendConnectPageState extends State<SendConnectPage> {
  MobileScannerController? _camera;
  Timer? _rescan;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.scannerBuilder == null && SendConnectPage.cameraSupported) {
      _camera = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.normal,
      );
    }
    final state = context.read<AppState>();
    unawaited(state.refreshDiscovery());
    _rescan = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      unawaited(context.read<AppState>().refreshDiscovery());
    });
  }

  @override
  void dispose() {
    _rescan?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  // ----- Connect paths -----

  Future<void> _onScannedRaw(String raw) async {
    if (_busy) return;
    final payload = ConnectPayload.tryParse(raw);
    if (payload == null) {
      _showError("That QR isn't a LanLink code.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await _camera?.stop();
    try {
      if (payload.needsHotspotJoin) {
        final joined = await WifiJoiner.join(
          payload.ssid!,
          payload.password ?? '',
        );
        if (!joined) {
          _showError(
            'Could not join "${payload.ssid}" automatically. '
            'Join it from Wi-Fi settings (password is on their screen), '
            'then come back.',
          );
          await _camera?.start();
          return;
        }
        // Let routes settle, then make sure discovery sees the new network.
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          await context.read<AppState>().refreshDiscovery();
        }
      }
      if (!mounted) return;
      final state = context.read<AppState>();
      // QR codes minted by v4 receivers carry a one-time connect token:
      // redeeming it pins the peer's fingerprint (verified) and consumes
      // the token so a replayed QR is rejected. Tokenless (older) codes
      // fall back to a plain probe.
      final token = payload.token;
      final probed = token != null && token.isNotEmpty
          ? await state.connectWithToken(payload.hostPort, token)
          : await state.probeManualPeer(payload.hostPort);
      if (!mounted) return;
      if (probed == null) {
        _showError("Connected to their network but couldn't reach "
            '"${payload.alias}". Keep both screens on and scan again.');
        await _camera?.start();
        return;
      }
      _goToSession(probed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      unawaited(_onScannedRaw(raw));
      return;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  void _goToSession(Device peer) {
    final state = context.read<AppState>();
    final nickname = state.settings.nicknameFor(peer.fingerprint);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SimpleSessionPage(
          peer: peer,
          peerDisplayName: nickname ??
              (peer.alias.trim().isEmpty ? 'the other device' : peer.alias),
        ),
      ),
    );
  }

  // ----- Build -----

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = context.watch<AppState>();
    final peers = state.peers.values.toList()
      ..sort((a, b) => a.alias.toLowerCase().compareTo(b.alias.toLowerCase()));
    final hasScanner =
        widget.scannerBuilder != null || SendConnectPage.cameraSupported;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pcMode ? 'Connect to a computer' : 'Send'),
        titleTextStyle: theme.textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.pcMode
                        ? 'Open LanLink on your computer and click '
                            'Receive — then scan the code on its screen.'
                        : 'On the other phone: tap Receive, then scan '
                            'its code below.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (hasScanner) ...[
                    _buildScanner(theme, scheme),
                    const SizedBox(height: 8),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.error, height: 1.4),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(child: Divider(color: scheme.outlineVariant)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          hasScanner ? 'or tap a nearby device' : 'Nearby',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(child: Divider(color: scheme.outlineVariant)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: peers.isEmpty
                        ? _buildSearching(theme, scheme)
                        : ListView.separated(
                            itemCount: peers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) =>
                                _buildPeerTile(theme, scheme, state, peers[i]),
                          ),
                  ),
                  if (Platform.isAndroid || widget.scannerBuilder != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const HostHotspotPage(),
                                ),
                              ),
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('No Wi-Fi here? Host a hotspot'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        textStyle: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanner(ThemeData theme, ColorScheme scheme) {
    final inner = widget.scannerBuilder != null
        ? widget.scannerBuilder!(
            context, (raw) => unawaited(_onScannedRaw(raw)))
        : MobileScanner(
            controller: _camera,
            onDetect: _onDetect,
            errorBuilder: (context, error, _) => ColoredBox(
              color: Colors.black87,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Camera unavailable — pick a device from the '
                    'list below instead.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          );
    return SizedBox(
      height: 240,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            inner,
            if (_busy)
              ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 12),
                      Text(
                        'Connecting…',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              )
            else
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withOpacity(0.85),
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearching(ThemeData theme, ColorScheme scheme) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 4),
            ),
            const SizedBox(height: 16),
            Text(
              'Looking for nearby devices…',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'They appear here when both devices are on the same Wi-Fi.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
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
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _busy ? null : () => _goToSession(peer),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.primary, width: 2),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, size: 26, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.chevron_right, size: 28, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
