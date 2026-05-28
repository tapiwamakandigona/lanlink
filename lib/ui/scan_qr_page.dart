import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../core/discovery/pair_payload.dart';
import '../state/app_state.dart';

/// Full-screen camera viewfinder that listens for LanLink pair QRs.
///
/// On a successful decode the page pops with the discovered alias so the
/// caller can show a snackbar without rebuilding everything. Camera is
/// disposed when the page leaves the tree.
class ScanQrPage extends StatefulWidget {
  const ScanQrPage({super.key});

  /// True only on platforms where `mobile_scanner` ships a working camera
  /// implementation. Hosts can call this before pushing the page to fail
  /// fast on desktop instead of seeing a black viewfinder.
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  @override
  State<ScanQrPage> createState() => _ScanQrPageState();
}

class _ScanQrPageState extends State<ScanQrPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );
  bool _handled = false;
  String? _lastError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled || !mounted) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final payload = PairPayload.tryParse(raw);
      if (payload == null) {
        setState(() =>
            _lastError = 'That QR code isn\'t a LanLink pair link.\n$raw');
        continue;
      }
      _handled = true;
      await _controller.stop();
      if (!mounted) return;
      final state = context.read<AppState>();
      final probed = await state.probeManualPeer(payload.hostPort);
      if (!mounted) return;
      Navigator.of(context).pop(probed?.alias ?? payload.alias);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan pair QR'),
        actions: [
          IconButton(
            tooltip: 'Toggle flash',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable: ${error.errorDetails?.message ?? error.errorCode.name}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
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
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              children: [
                if (_lastError != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _lastError!,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Point the camera at the other phone\'s LanLink QR.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
