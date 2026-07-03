import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/discovery/connect_payload.dart';
import '../../core/models/device.dart';
import '../../core/models/file_info.dart';
import '../../core/platform/wifi_joiner.dart';
import '../../state/app_state.dart';
import '../picker/share_picker_page.dart';
import '../v4/v4.dart';
import 'session_display.dart';

const _uuid = Uuid();

/// Send: exactly three ways to reach a device —
///  1. tap it on the radar (LAN discovery),
///  2. scan its QR (one-time token → verified connect),
///  3. type its address (Direct Link → probe + pin).
///
/// Whichever path is used, the page then stages files (system picker, or
/// the photos/apps picker on Android) and hands off to `sendFiles`.
class SendPage extends StatefulWidget {
  const SendPage({super.key, this.prestagedFiles, this.scannerBuilder});

  /// Files staged before the page opened (Android share-into-app).
  final List<FileInfo>? prestagedFiles;

  /// Test hook: replaces the live camera preview inside the scan frame.
  final Widget Function(BuildContext, void Function(String raw))?
      scannerBuilder;

  /// mobile_scanner only ships a camera implementation on phones.
  static bool get cameraSupported => Platform.isAndroid || Platform.isIOS;

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final _hostPortCtrl = TextEditingController();
  MobileScannerController? _camera;
  Timer? _rescan;
  bool _busy = false;
  bool _scanning = false;
  String? _error;
  late List<FileInfo> _staged;

  @override
  void initState() {
    super.initState();
    _staged = List.of(widget.prestagedFiles ?? const []);
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
    _hostPortCtrl.dispose();
    super.dispose();
  }

  // ─── Connect path 2: QR scan ─────────────────────────────────────────

  void _toggleScanner() {
    setState(() {
      _scanning = !_scanning;
      _error = null;
      if (_scanning &&
          widget.scannerBuilder == null &&
          SendPage.cameraSupported) {
        _camera ??= MobileScannerController(
          formats: const [BarcodeFormat.qrCode],
          detectionSpeed: DetectionSpeed.normal,
        );
      } else if (!_scanning) {
        unawaited(_camera?.stop());
      }
    });
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      unawaited(_onScannedRaw(raw));
      return;
    }
  }

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
    final state = context.read<AppState>();
    await _camera?.stop();
    try {
      // Hotspot-shaped QR: join the receiver's network first, then connect.
      if (payload.needsHotspotJoin) {
        final joined =
            await WifiJoiner.join(payload.ssid!, payload.password ?? '');
        if (!joined) {
          _showError('Could not join "${payload.ssid}" automatically. '
              'Join it from Wi-Fi settings, then scan again.');
          await _camera?.start();
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (mounted) await context.read<AppState>().refreshDiscovery();
      }
      if (!mounted) return;
      // v4 QRs carry a one-time token: redeeming pins the fingerprint
      // (verified). Legacy tokenless codes fall back to a plain probe.
      final token = payload.token;
      final peer = token != null && token.isNotEmpty
          ? await state.connectWithToken(payload.hostPort, token)
          : await state.probeManualPeer(payload.hostPort);
      if (!mounted) return;
      if (peer == null) {
        _showError('Couldn\'t reach "${payload.alias}". Keep both screens '
            'on and scan again — their code refreshes when LanLink reopens.');
        await _camera?.start();
        return;
      }
      await _sendTo(peer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── Connect path 3: Direct Link ─────────────────────────────────────

  Future<void> _connectDirect() async {
    final hostPort = _hostPortCtrl.text.trim();
    if (hostPort.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final peer =
          await context.read<AppState>().probeManualPeer(hostPort);
      if (!mounted) return;
      if (peer == null) {
        _showError('No LanLink device answered at $hostPort. '
            'Check the address on their Receive screen.');
        return;
      }
      await _sendTo(peer);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── Staging + send ──────────────────────────────────────────────────

  Future<void> _sendTo(Device peer) async {
    final files = _staged.isNotEmpty ? _staged : await _pickFiles();
    if (files.isEmpty || !mounted) return;
    final state = context.read<AppState>();
    await state.sendFiles(peer: peer, files: files);
    if (!mounted) return;
    // Back to home, where the session card shows live progress.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<List<FileInfo>> _pickFiles() async {
    // Android gets the friendlier photos/apps picker with a "browse files"
    // escape hatch; everything else goes straight to the system dialog.
    if (Platform.isAndroid) {
      final picked = await SharePickerPage.open(context);
      return picked ?? const [];
    }
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
    } catch (_) {
      _showError('LanLink could not open the system file dialog. '
          'On Linux, installing zenity usually fixes this.');
      return const [];
    }
    if (result == null) return const [];
    return [
      for (final f in result.files)
        if (f.path != null)
          FileInfo(
            id: _uuid.v4(),
            fileName: f.name,
            size: f.size,
            fileType: fileTypeForName(f.name),
            localPath: f.path,
          ),
    ];
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  // ─── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final peers = state.peers.values.toList()
      ..sort((a, b) => a.alias.toLowerCase().compareTo(b.alias.toLowerCase()));
    final hasScanner =
        widget.scannerBuilder != null || SendPage.cameraSupported;

    return Scaffold(
      appBar: AppBar(title: const Text('Send')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(VSpace.x5),
              children: [
                if (_staged.isNotEmpty) ...[
                  Text(
                    _staged.length == 1
                        ? 'Ready to send ${_staged.first.fileName}'
                        : 'Ready to send ${_staged.length} files',
                    style: VType.bodyStrong.copyWith(color: scheme.onSurface),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: VSpace.x4),
                ],
                Text('Nearby devices',
                    style: VType.heading.copyWith(color: scheme.onSurface)),
                const SizedBox(height: VSpace.x1),
                Text(
                  'Tap a device to choose files and send.',
                  style: VType.caption.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: VSpace.x4),
                DeviceRadar(
                  peers: [
                    for (final p in peers) radarPeerData(state.settings, p),
                  ],
                  searching: true,
                  onPeerTap: (tapped) {
                    final peer = peers.firstWhere(
                      (p) =>
                          displayPeerName(state.settings, p) == tapped.name,
                      orElse: () => peers.first,
                    );
                    if (!_busy) unawaited(_sendTo(peer));
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: VSpace.x4),
                  Text(
                    _error!,
                    style: VType.body.copyWith(color: context.ember.danger),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: VSpace.x6),
                if (hasScanner) ...[
                  if (_scanning) ...[
                    QrScanFrame(child: _buildScanner()),
                    const SizedBox(height: VSpace.x2),
                    TextButton(
                      onPressed: _toggleScanner,
                      child: const Text('Hide camera'),
                    ),
                  ] else
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _toggleScanner,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan their code'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  const SizedBox(height: VSpace.x4),
                ],
                _DirectLinkField(
                  controller: _hostPortCtrl,
                  busy: _busy,
                  onConnect: _connectDirect,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanner() {
    if (widget.scannerBuilder != null) {
      return widget.scannerBuilder!(
          context, (raw) => unawaited(_onScannedRaw(raw)));
    }
    final scheme = Theme.of(context).colorScheme;
    return MobileScanner(
      controller: _camera,
      onDetect: _onDetect,
      errorBuilder: (context, error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(VSpace.x4),
          child: Text(
            'Camera unavailable — tap a nearby device or use Direct Link.',
            textAlign: TextAlign.center,
            style: VType.body.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Connect path 3: type the host:port shown on the receiver's screen.
class _DirectLinkField extends StatelessWidget {
  const _DirectLinkField({
    required this.controller,
    required this.busy,
    required this.onConnect,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Direct Link',
            style: VType.label.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: VSpace.x2),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !busy,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: '192.168.1.20:53317',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => onConnect(),
              ),
            ),
            const SizedBox(width: VSpace.x2),
            FilledButton.tonal(
              onPressed: busy ? null : onConnect,
              child: const Text('Connect'),
            ),
          ],
        ),
        const SizedBox(height: VSpace.x1),
        Text(
          "Type the address shown on the other device's Receive screen.",
          style: VType.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
