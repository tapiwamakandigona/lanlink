import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/discovery/connect_payload.dart';
import '../../state/app_state.dart';
import '../v4/v4.dart';

/// Receive: shows the connect QR the instant it opens. The QR carries
/// host:port plus a one-time connect token; the local address is shown as
/// the Direct Link fallback for devices without a camera.
///
/// Connect tokens live in receiver memory only, so the payload (and QR) is
/// re-minted every time the app comes back to the foreground — a QR from
/// before a restart would carry a dead token.
class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key, this.debugPayload});

  /// Test hook: skips live state and renders exactly this payload.
  final ConnectPayload? debugPayload;

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> with WidgetsBindingObserver {
  ConnectPayload? _payload;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mintPayload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    // Tokens are in-memory and single-use: regenerate whenever we resume so
    // the QR on screen is always redeemable.
    if (lifecycleState == AppLifecycleState.resumed) _mintPayload();
  }

  void _mintPayload() {
    if (widget.debugPayload != null) {
      setState(() => _payload = widget.debugPayload);
      return;
    }
    final state = context.read<AppState>();
    final port = state.port;
    if (port == null || state.localIps.isEmpty) {
      setState(() => _payload = null);
      return;
    }
    setState(() {
      _payload = ConnectPayload(
        ip: state.localIps.first,
        port: port,
        alias: state.displayAlias,
        fingerprint: state.fingerprint,
        token: state.issueConnectToken(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final payload = _payload;
    // Tokens are single-use: the moment a sender redeems the displayed
    // one, re-mint so the QR on screen is always valid (a second device
    // can scan right away).
    final token = payload?.token;
    if (widget.debugPayload == null &&
        token != null &&
        !state.isConnectTokenValid(token)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = _payload?.token;
        if (current != null && !state.isConnectTokenValid(current)) {
          _mintPayload();
        }
      });
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(VSpace.x6),
              child: payload == null
                  ? _Unavailable(scheme: scheme, onRetry: _mintPayload)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        QrDisplayPanel(
                          payload: payload.toQrString(),
                          deviceName: state.displayAlias,
                        ),
                        const SizedBox(height: VSpace.x6),
                        Text(
                          'No camera on the other device?',
                          style: VType.label
                              .copyWith(color: scheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: VSpace.x1),
                        Text(
                          'Use Direct Link and type ${payload.hostPort}',
                          style: VType.bodyStrong
                              .copyWith(color: scheme.onSurface),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.scheme, required this.onRetry});

  final ColorScheme scheme;

  /// Re-attempts minting the connect payload (e.g. after Wi-Fi came back).
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.wifi_off, size: 40, color: scheme.onSurfaceVariant),
        const SizedBox(height: VSpace.x4),
        Text(
          "Receiving isn't available right now",
          style: VType.heading.copyWith(color: scheme.onSurface),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: VSpace.x2),
        Text(
          'LanLink could not start listening on this network. '
          'Check your Wi-Fi connection and try again.',
          style: VType.body.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: VSpace.x5),
        FilledButton.tonalIcon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}
