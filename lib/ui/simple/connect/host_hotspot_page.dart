import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/models/device.dart';
import '../../../core/platform/local_hotspot.dart';
import '../../../state/app_state.dart';
import 'simple_session_page.dart';

/// "No Wi-Fi here? Host a hotspot" — the phone reverses roles and becomes
/// the network. Shows the hotspot name + password in big text (laptops
/// can't scan QRs, so joining is the one manual step) plus a Wi-Fi QR for
/// devices that can scan. The moment the other device joins and LanLink
/// announces itself, both land on the connected screen automatically.
class HostHotspotPage extends StatefulWidget {
  const HostHotspotPage({super.key, this.debugInfo});

  /// Test hook: skips platform calls and renders this hotspot as running.
  final HotspotInfo? debugInfo;

  @override
  State<HostHotspotPage> createState() => _HostHotspotPageState();
}

class _HostHotspotPageState extends State<HostHotspotPage> {
  late final AppState _state;
  late final Set<String> _knownPeers;

  HotspotInfo? _info;
  String? _error;
  bool _starting = true;
  bool _navigated = false;
  Timer? _rescan;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _knownPeers = _state.peers.keys.toSet();
    _state.addListener(_onStateChanged);
    if (widget.debugInfo != null) {
      _info = widget.debugInfo;
      _starting = false;
    } else {
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    _rescan?.cancel();
    _state.removeListener(_onStateChanged);
    if (_info != null && !_navigated && widget.debugInfo == null) {
      unawaited(LocalHotspot.stop());
    }
    super.dispose();
  }

  Future<void> _start() async {
    if (!await LocalHotspot.isSupported()) {
      _fail('This phone cannot create a hotspot from an app. '
          'Use the regular hotspot in quick settings instead, then '
          'connect the computer to it.');
      return;
    }
    if (!await LocalHotspot.hasPermission() &&
        !await LocalHotspot.requestPermission()) {
      _fail('Android requires the location permission before an app may '
          'create a hotspot — LanLink only uses it for that.');
      return;
    }
    final info = await LocalHotspot.start();
    if (!mounted) return;
    if (info == null) {
      _fail("Couldn't start the hotspot. If the regular hotspot or "
          'tethering is on, turn it off and try again.');
      return;
    }
    setState(() {
      _info = info;
      _starting = false;
    });
    // The hotspot interface is new — keep discovery sweeping so the
    // joining device pops in as soon as it's reachable.
    await _state.refreshDiscovery();
    _rescan = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      unawaited(_state.refreshDiscovery());
    });
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _starting = false;
    });
  }

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
          hotspotHosted: widget.debugInfo == null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Host a hotspot')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _starting
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildError(theme, scheme)
                      : _buildRunning(theme, scheme, _info!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme, ColorScheme scheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 56, color: scheme.error),
        const SizedBox(height: 20),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(height: 1.5),
        ),
      ],
    );
  }

  Widget _buildRunning(ThemeData theme, ColorScheme scheme, HotspotInfo info) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This phone is now a Wi-Fi network',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'On the computer, click the Wi-Fi icon, choose this '
            'network and type the password:',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          _credCard(theme, scheme, 'Network', info.ssid),
          const SizedBox(height: 10),
          _credCard(theme, scheme, 'Password', info.password),
          const SizedBox(height: 18),
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
                  'Waiting for the other device to join…',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Text(
                  'Phones can scan this instead:',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: QrImageView(
                    data: info.toWifiQrString(),
                    size: 140,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _credCard(
    ThemeData theme,
    ColorScheme scheme,
    String label,
    String value,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
