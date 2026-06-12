import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/discovery/connect_payload.dart';
import '../../../core/models/device.dart';
import '../../../core/platform/local_hotspot.dart';
import '../../../core/protocol/constants.dart';
import '../../../state/app_state.dart';
import 'simple_session_page.dart';

/// Simple-mode Receive: shows one big QR the instant it opens.
///
/// The page silently picks the right payload:
/// * On a network → pairing code (`ip:port + token`), sender connects
///   directly.
/// * No network (Android) → starts a LocalOnlyHotspot and bakes the
///   hotspot credentials into the same QR, so one scan joins + connects.
///
/// When a sender registers with us, the page swaps itself for the
/// connected session screen — the receiver never taps anything.
class ReceiveQrPage extends StatefulWidget {
  const ReceiveQrPage({super.key, this.debugPayload});

  /// Test hook: skips network/hotspot probing and renders this payload.
  final ConnectPayload? debugPayload;

  @override
  State<ReceiveQrPage> createState() => _ReceiveQrPageState();
}

class _ReceiveQrPageState extends State<ReceiveQrPage> {
  late final AppState _state;

  /// Peers we already knew before the QR went up — only a *new* arrival
  /// (or a fresh announcement from a known one) counts as "they scanned".
  late final Set<String> _knownPeers;

  ConnectPayload? _payload;
  String? _message;
  bool _hotspotRunning = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _knownPeers = _state.peers.keys.toSet();
    _state.addListener(_onStateChanged);
    if (widget.debugPayload != null) {
      _payload = widget.debugPayload;
    } else {
      unawaited(_preparePayload());
    }
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    if (_hotspotRunning) {
      unawaited(LocalHotspot.stop());
    }
    super.dispose();
  }

  String get _selfAlias {
    final alias = _state.settings.alias.trim();
    return alias.isEmpty ? 'LanLink' : alias;
  }

  Future<void> _preparePayload() async {
    final port = _state.port ?? LanLinkProtocol.defaultPort;
    final ips = _state.localIps;
    if (ips.isNotEmpty) {
      // Same-network shape: instant connect for anyone on this Wi-Fi.
      setState(() {
        _payload = ConnectPayload(
          ip: ips.first,
          port: port,
          alias: _selfAlias,
          fingerprint: _state.fingerprint,
        );
      });
      return;
    }
    // No network at all — host one ourselves (Android only).
    if (Platform.isAndroid && await LocalHotspot.isSupported()) {
      if (!await LocalHotspot.hasPermission() &&
          !await LocalHotspot.requestPermission()) {
        _fail('LanLink needs the location permission to create a '
            'hotspot. You can also join the same Wi-Fi instead.');
        return;
      }
      final info = await LocalHotspot.start();
      if (!mounted) return;
      if (info == null) {
        _fail("Couldn't start a hotspot. Join the same Wi-Fi on both "
            'devices and try again.');
        return;
      }
      _hotspotRunning = true;
      await _state.refreshDiscovery();
      if (!mounted) return;
      final hostIp = info.hostIps.isNotEmpty
          ? info.hostIps.first
          : (_state.localIps.isNotEmpty ? _state.localIps.first : '0.0.0.0');
      setState(() {
        _payload = ConnectPayload(
          ip: hostIp,
          port: _state.port ?? port,
          alias: _selfAlias,
          fingerprint: _state.fingerprint,
          ssid: info.ssid,
          password: info.password,
        );
      });
      return;
    }
    _fail('Connect this device to a Wi-Fi network (or a phone hotspot) '
        'and try again.');
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _message = message);
  }

  /// A sender that scanned us probes/registers, which lands it in the
  /// peer map — that's our cue that the two devices found each other.
  void _onStateChanged() {
    if (_navigated || !mounted) return;
    for (final entry in _state.peers.entries) {
      if (_knownPeers.contains(entry.key)) continue;
      _navigated = true;
      _goToSession(entry.value);
      return;
    }
  }

  void _goToSession(Device peer) {
    final nickname = _state.settings.nicknameFor(peer.fingerprint);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SimpleSessionPage(
          peer: peer,
          peerDisplayName: nickname ??
              (peer.alias.trim().isEmpty ? 'the other device' : peer.alias),
          hotspotHosted: _hotspotRunning,
        ),
      ),
    );
    // Session page owns the hotspot lifetime from here.
    _hotspotRunning = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final payload = _payload;
    return Scaffold(
      appBar: AppBar(title: const Text('Receive')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _message != null
                  ? _buildMessage(theme, scheme)
                  : payload == null
                      ? const Center(child: CircularProgressIndicator())
                      : _buildQr(theme, scheme, payload),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessage(ThemeData theme, ColorScheme scheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.wifi_off, size: 56, color: scheme.onSurfaceVariant),
        const SizedBox(height: 20),
        Text(
          _message!,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(height: 1.5),
        ),
      ],
    );
  }

  Widget _buildQr(ThemeData theme, ColorScheme scheme, ConnectPayload p) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Show this code to the sender',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            p.needsHotspotJoin
                ? 'No Wi-Fi needed — scanning connects them straight '
                    'to this phone.'
                : 'On their phone: tap Send, then point the camera here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: QrImageView(
                data: p.toQrString(),
                size: 260,
                backgroundColor: Colors.white,
                errorCorrectionLevel: QrErrorCorrectLevel.M,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Waiting for them to scan…',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'They can also pick “$_selfAlias” from their nearby list.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
