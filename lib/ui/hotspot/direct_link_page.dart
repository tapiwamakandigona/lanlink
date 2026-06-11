import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/platform/local_hotspot.dart';
import '../../core/platform/system_settings.dart';
import '../../state/app_state.dart';

/// "Direct link" — file transfer with no router and no internet.
///
/// On Android this page hosts a LocalOnlyHotspot automatically and shows
/// a standard Wi-Fi QR code: the other device scans it with its stock
/// camera (works on Android *and* iPhone), joins the temporary network,
/// opens LanLink, and discovery does the rest.
///
/// On Windows we can't create a hotspot programmatically, so the page
/// deep-links into the Mobile Hotspot settings pane and explains the two
/// manual taps. macOS can't host at all — the page says to let the phone
/// host instead.
class DirectLinkPage extends StatefulWidget {
  const DirectLinkPage({super.key, this.debugInfo});

  /// Screenshot/golden-test hook: when set, the page skips the platform
  /// calls entirely and renders the running-hotspot UI with this info.
  @visibleForTesting
  final HotspotInfo? debugInfo;

  @override
  State<DirectLinkPage> createState() => _DirectLinkPageState();
}

enum _Phase { checking, needsPermission, starting, running, failed }

class _DirectLinkPageState extends State<DirectLinkPage> {
  _Phase _phase = _Phase.checking;
  HotspotInfo? _info;
  String? _error;

  /// Peer count when the hotspot came up — used to flash a "connected!"
  /// banner as soon as somebody new appears.
  int _peersAtStart = 0;

  bool get _isAndroid => widget.debugInfo != null || Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    final debugInfo = widget.debugInfo;
    if (debugInfo != null) {
      _phase = _Phase.running;
      _info = debugInfo;
      return;
    }
    if (_isAndroid) _bootstrap();
  }

  Future<void> _bootstrap() async {
    final supported = await LocalHotspot.isSupported();
    if (!mounted) return;
    if (!supported) {
      setState(() {
        _phase = _Phase.failed;
        _error = 'This phone does not support creating a hotspot from an '
            'app (needs Android 8 or newer).';
      });
      return;
    }
    final granted = await LocalHotspot.hasPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _phase = _Phase.needsPermission);
      return;
    }
    await _start();
  }

  Future<void> _requestPermission() async {
    final ok = await LocalHotspot.requestPermission();
    if (!mounted) return;
    if (ok) {
      await _start();
    } else {
      setState(() {
        _phase = _Phase.failed;
        _error = 'Permission was declined. LanLink needs it only to create '
            'the hotspot — nothing is tracked.';
      });
    }
  }

  Future<void> _start() async {
    setState(() => _phase = _Phase.starting);
    final info = await LocalHotspot.start();
    if (!mounted) return;
    if (info == null) {
      setState(() {
        _phase = _Phase.failed;
        _error = 'Could not start the hotspot. Two usual causes:\n'
            '• Location is switched off — turn it on and retry.\n'
            '• Regular hotspot/tethering is already running — turn it off '
            'first.';
      });
      return;
    }
    setState(() {
      _phase = _Phase.running;
      _info = info;
      _peersAtStart = context.read<AppState>().peers.length;
    });
  }

  Future<void> _stopAndClose() async {
    await LocalHotspot.stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Direct link — no Wi-Fi needed')),
      body: _isAndroid ? _buildAndroid(context) : _buildDesktop(context),
    );
  }

  // ----- Android: automatic hotspot + QR -----

  Widget _buildAndroid(BuildContext context) {
    switch (_phase) {
      case _Phase.checking:
      case _Phase.starting:
        return const Center(child: CircularProgressIndicator());
      case _Phase.needsPermission:
        return _MessagePane(
          icon: Icons.wifi_tethering,
          title: 'One quick permission',
          body: 'Android asks for a "nearby devices" (or location) '
              'permission before an app may create a hotspot. LanLink uses '
              'it only for that.',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Allow and continue'),
              onPressed: _requestPermission,
            ),
          ],
        );
      case _Phase.failed:
        return _MessagePane(
          icon: Icons.error_outline,
          title: "Couldn't start the hotspot",
          body: _error ?? 'Unknown error.',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
              onPressed: _bootstrap,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('Open hotspot settings'),
              onPressed: SystemSettings.openHotspotSettings,
            ),
          ],
        );
      case _Phase.running:
        return _buildRunning(context, _info!);
    }
  }

  Widget _buildRunning(BuildContext context, HotspotInfo info) {
    final theme = Theme.of(context);
    final peers = context.watch<AppState>().peers;
    final connected = peers.length > _peersAtStart;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (connected)
          Card(
            color: theme.colorScheme.primaryContainer,
            child: ListTile(
              leading: const Icon(Icons.celebration),
              title: const Text('Device connected!'),
              subtitle: const Text('Go back and pick what to send.'),
              trailing: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Send files'),
              ),
            ),
          )
        else
          const Card(
            child: ListTile(
              leading: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              title: Text('Hotspot is on — waiting for the other device'),
              subtitle: Text('It joins, opens LanLink, and appears '
                  'here automatically.'),
            ),
          ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: info.toWifiQrString(),
              size: 240,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'On the other device: open the normal camera, point it at this '
          'code, tap "Join network". Works on Android and iPhone.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Text('Or join by hand:', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _CredentialRow(label: 'Network', value: info.ssid),
        _CredentialRow(label: 'Password', value: info.password),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          icon: const Icon(Icons.power_settings_new),
          label: const Text('Turn hotspot off'),
          onPressed: _stopAndClose,
        ),
        const SizedBox(height: 8),
        Text(
          'The hotspot stays on while you transfer and switches off when '
          'you tap the button above or close LanLink.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  // ----- Desktop fallbacks -----

  Widget _buildDesktop(BuildContext context) {
    if (Platform.isWindows) {
      return _MessagePane(
        icon: Icons.wifi_tethering,
        title: 'Turn on Mobile Hotspot',
        body: '1. Open Windows Settings → Network & internet → Mobile '
            'hotspot and switch it on.\n'
            '2. On the other device, join that network (name and password '
            'are shown on the same screen).\n'
            '3. Open LanLink on both — they find each other automatically.',
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Open Mobile hotspot settings'),
            onPressed: () {
              Process.run('cmd', [
                '/c',
                'start',
                'ms-settings:network-mobilehotspot',
              ]);
            },
          ),
        ],
      );
    }
    return const _MessagePane(
      icon: Icons.phone_iphone,
      title: 'Let the phone host',
      body: 'This computer cannot create a hotspot, but any Android phone '
          'in the pair can: open LanLink there and choose "Direct link". '
          'Then join the network it shows, and the devices will find each '
          'other.',
      actions: [],
    );
  }
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$label copied')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MessagePane extends StatelessWidget {
  const _MessagePane({
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
  });
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(body, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 24),
              ...actions.expand((w) => [w, const SizedBox(height: 8)]),
            ],
          ),
        ),
      ),
    );
  }
}
