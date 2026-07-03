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
import '../../core/platform/system_settings.dart';
import '../../core/platform/wifi_joiner.dart';
import '../../state/app_state.dart';
import '../picker/share_picker_page.dart';
import '../v4/direct_connect/connect_router.dart';
import '../v4/direct_connect/join_fallback_sheet.dart';
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
  const SendPage({
    super.key,
    this.prestagedFiles,
    this.targetPeer,
    this.scannerBuilder,
    this.connectRouter,
  });

  /// Files staged before the page opened (Android share-into-app).
  final List<FileInfo>? prestagedFiles;

  /// When set (the "Send files" action on a linked session, F3), the page
  /// goes straight to picking files for this peer — no radar tap or scan
  /// needed. Cancelling the picker leaves the normal send page up.
  final Device? targetPeer;

  /// Test hook: replaces the live camera preview inside the scan frame.
  final Widget Function(BuildContext, void Function(String raw))?
      scannerBuilder;

  /// Test hook: routing probe/join with faked network + platform calls.
  final ConnectRouter? connectRouter;

  /// mobile_scanner only ships a camera implementation on phones.
  static bool get cameraSupported => Platform.isAndroid || Platform.isIOS;

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> with WidgetsBindingObserver {
  final _hostPortCtrl = TextEditingController();
  MobileScannerController? _camera;
  Timer? _rescan;
  bool _busy = false;

  /// True only while a QR redeem / Direct Link probe is on the wire, so
  /// the UI can show live "Connecting…" feedback (not just disable
  /// buttons).
  bool _connecting = false;
  bool _scanning = false;
  String? _error;
  late List<FileInfo> _staged;

  /// One friendly line under the radar while the smart routing runs
  /// ("Joining their link…"), instead of the bare "Connecting…".
  String? _progressLine;

  /// True after we programmatically joined a receiver-hosted hotspot, so
  /// leaving the page can release the network binding again.
  bool _joinedHotspot = false;

  /// True once a send session was handed off to AppState — the transfer
  /// keeps using the joined network after this page pops, so don't
  /// release it on dispose.
  bool _handedOff = false;

  /// True while the Tier-2/3 probe loop waits for the PC to become
  /// reachable, so the UI can show a Cancel affordance instead of
  /// spinner-locking the page for up to 90 s.
  bool _probeWaiting = false;

  /// Set by the Cancel button (or dispose) to abort the probe loop.
  bool _probeCancelled = false;

  /// True while the Tier-1 programmatic join waits on the Android system
  /// dialog (up to ~60 s + a silent retry) — shows a Cancel affordance so
  /// the user isn't spinner-locked for minutes.
  bool _joinWaiting = false;

  /// Completed by the Cancel button to abandon the in-flight Tier-1 join.
  Completer<void>? _joinCancel;

  /// Monotonic connect-attempt id: every new connect (and every abandon)
  /// bumps it, so late results from an abandoned attempt are ignored —
  /// the Dart-side twin of the platform joiner's `joinAttemptId` guard.
  int _attempt = 0;

  /// The Settings-handoff target (Tier 2/3): kept while the user is out in
  /// the system UI so returning to the app can automatically re-check
  /// reachability instead of silently dropping the flow.
  ConnectPayload? _pendingFallback;
  ConnectRouter? _pendingRouter;

  /// When set, the error banner grows a Retry button running this action.
  VoidCallback? _retryAction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _staged = List.of(widget.prestagedFiles ?? const []);
    final state = context.read<AppState>();
    // Opening the page is an explicit user action: probe everything and
    // restart any in-flight sweep so results reflect the current network.
    unawaited(state.refreshDiscovery(userInitiated: true));
    _rescan = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      unawaited(context.read<AppState>().refreshDiscovery());
    });
    // Linked-session send-back: skip straight to the file picker for the
    // peer we're already paired with.
    final target = widget.targetPeer;
    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_sendTo(target));
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    // U3: coming back from the Tier-2/3 Settings hand-off must not be a
    // silent drop — re-check whether the pending target became reachable.
    if (lifecycleState == AppLifecycleState.resumed) {
      unawaited(_recheckPendingFallback());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attempt++; // invalidate any in-flight connect attempt
    _rescan?.cancel();
    _camera?.dispose();
    _hostPortCtrl.dispose();
    // Guest teardown: if we joined a receiver's hotspot but never handed a
    // transfer off, release the binding so the phone returns to its own
    // network. An in-flight transfer keeps the binding (the session owns
    // it from here; disconnect/teardown releases it later).
    _probeCancelled = true; // abort any in-flight Tier-2/3 probe loop
    if (_joinedHotspot && !_handedOff) {
      // Clear the network-lost handler alongside the release: leave()'s
      // queued onLost must not fire a stale closure over this dead State.
      WifiJoiner.setOnNetworkLost(null);
      unawaited(WifiJoiner.leave());
    }
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
    final payload = ConnectPayload.tryParse(raw);
    if (payload == null) {
      _showError("That QR isn't a LanLink code.");
      return;
    }
    await _connectToPayload(payload);
  }

  Future<void> _connectToPayload(ConnectPayload payload) async {
    if (_busy) return;
    final attempt = ++_attempt;
    _clearPendingFallback(); // a fresh connect supersedes any old hand-off
    setState(() {
      _busy = true;
      _connecting = true;
      _error = null;
      _retryAction = null;
    });
    final state = context.read<AppState>();
    await _camera?.stop();
    try {
      // Smart routing: try the peer on the current network first (fast
      // probe); only when it's unreachable AND the QR carries hotspot
      // credentials do we auto-join the receiver's link (Tier 1), falling
      // back to the Settings-based joins (Tiers 2/3) when that fails.
      if (payload.needsHotspotJoin) {
        final router = widget.connectRouter ?? ConnectRouter();
        setState(() => _progressLine = 'Reaching ${payload.alias}…');
        final cancel = _joinCancel = Completer<void>();
        final decideFuture = router.decide(payload, onJoinStart: () {
          // The #1 real-world failure: users don't know the system dialog
          // needs a tap. Tell them exactly what to do while it's up —
          // and show a Cancel so they aren't spinner-locked for minutes.
          if (mounted && attempt == _attempt) {
            setState(() {
              _joinWaiting = true;
              _progressLine = 'Android will show a connection dialog — '
                  'tap "${payload.ssid}", then Connect.';
            });
          }
        });
        // U1: race the join against the Cancel button — null == cancelled.
        final decision = await Future.any<RouteDecision?>([
          decideFuture,
          cancel.future.then((_) => null),
        ]);
        if (!mounted || attempt != _attempt) return;
        setState(() => _joinWaiting = false);
        if (decision == null) {
          // Cancelled mid Tier-1 join: abort the pending platform request
          // (leave() bumps the platform-side joinAttemptId and releases
          // the specifier callback, dismissing the system dialog), and —
          // belt and braces — release any late successful bind from the
          // abandoned future before surfacing the Tier-2/3 options.
          _attempt++;
          unawaited(WifiJoiner.leave());
          unawaited(decideFuture.then((late) {
            if (late.route == ConnectRoute.joinedHotspot) {
              unawaited(WifiJoiner.leave());
            }
          }));
          final resumed = await _runJoinFallback(payload, router);
          if (!resumed) {
            await _camera?.start();
            return;
          }
          await _completeConnect(state, payload);
          return;
        }
        switch (decision.route) {
          case ConnectRoute.direct:
          case ConnectRoute.unreachable:
            // Already reachable on this network (or nothing smarter to
            // try): fall through to the normal connect below, which owns
            // the friendly error.
            break;
          case ConnectRoute.joinFailed:
            // Tiers 2/3: Settings-based joins. When one of them makes the
            // PC reachable we resume the normal connect below — the
            // network is joined at DEVICE level then (no process binding),
            // so _joinedHotspot stays false and Disconnect has nothing to
            // release.
            final resumed = await _runJoinFallback(payload, router,
                reason: decision.joinResult);
            if (!resumed) {
              await _camera?.start();
              return;
            }
            if (attempt != _attempt) return;
          case ConnectRoute.joinedHotspot:
            _joinedHotspot = true;
            // The join's network callback stays registered for the whole
            // session; surface an OS-side drop while this page still owns
            // the binding (AppState takes over after hand-off).
            WifiJoiner.setOnNetworkLost(() {
              if (mounted && !_handedOff) {
                _showError('The link to "${payload.alias}" dropped. '
                    'Scan their code again to reconnect.');
              }
            });
            if (mounted) {
              setState(
                  () => _progressLine = 'Joined their link — waiting for the '
                      'network to be ready…');
            }
            // U2: a fixed "settle" delay races slow DHCP and then dies
            // silently on the single probe below. Poll the target instead
            // — every ~1 s for up to ~12 s — and only fail (loudly, with
            // a Retry) once the loop exhausts.
            final ready = await router.waitForReachable(
              payload,
              interval: const Duration(seconds: 1),
              overall: const Duration(seconds: 12),
              isCancelled: () => !mounted || attempt != _attempt,
            );
            if (!mounted || attempt != _attempt) return;
            if (!ready) {
              _showError(
                'Joined "${payload.ssid}", but ${payload.alias} isn\'t '
                'answering yet — its network may still be starting up. '
                'Wait a few seconds and retry.',
                retry: () => unawaited(_connectToPayload(payload)),
              );
              await _camera?.start();
              return;
            }
            if (mounted) {
              setState(() => _progressLine = 'Joined their link — connecting…');
              // Just joined their link: force a fresh sweep of the new
              // network (incl. hotspot prefixes) instead of piggybacking
              // on a stale in-flight scan.
              await context
                  .read<AppState>()
                  .refreshDiscovery(userInitiated: true);
            }
        }
      }
      if (!mounted || attempt != _attempt) return;
      await _completeConnect(state, payload);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _connecting = false;
          _joinWaiting = false;
          _progressLine = null;
        });
      }
    }
  }

  /// The tail of every connect path: redeem the one-time token (v4 QRs —
  /// pins the fingerprint) or plain-probe legacy codes, then hand off to
  /// file staging.
  Future<void> _completeConnect(AppState state, ConnectPayload payload) async {
    final token = payload.token;
    final peer = token != null && token.isNotEmpty
        ? await state.connectWithToken(payload.hostPort, token)
        : await state.probeManualPeer(payload.hostPort);
    if (!mounted) return;
    setState(() => _connecting = false);
    if (peer == null) {
      _showError('Couldn\'t reach "${payload.alias}". Keep both screens '
          'on and scan again — their code refreshes automatically.');
      await _camera?.start();
      return;
    }
    await _sendTo(peer);
  }

  /// Tier-2/3 join fallback after a failed programmatic (Tier-1) join:
  /// offers the system "Add networks" panel or manual Wi-Fi settings via a
  /// bottom sheet, then polls the QR payload's ip:port until the PC is
  /// reachable. Returns true when the connect flow should resume exactly
  /// as a successful Tier-1 join would.
  Future<bool> _runJoinFallback(
    ConnectPayload payload,
    ConnectRouter router, {
    WifiJoinResult? reason,
  }) async {
    if (!mounted) return false;
    setState(() {
      _connecting = false;
      _progressLine = null;
    });
    final canAddNetwork = await WifiJoiner.isAddNetworksSupported();
    if (!mounted) return false;
    final action = await showModalBottomSheet<JoinFallbackAction>(
      context: context,
      isScrollControlled: true,
      builder: (_) => JoinFallbackSheet(
        ssid: payload.ssid!,
        password: payload.password ?? '',
        canAddNetwork: canAddNetwork,
        reason: reason,
      ),
    );
    if (!mounted || action == null) {
      _clearPendingFallback(); // user opted out — no re-check on resume
      return false;
    }
    // U3: the user is about to leave for the system UI — remember the
    // target so resuming the app re-checks it instead of dropping the
    // flow silently (see [_recheckPendingFallback]).
    _pendingFallback = payload;
    _pendingRouter = router;
    switch (action) {
      case JoinFallbackAction.addNetwork:
        final saved = await WifiJoiner.fallbackAddNetwork(
            payload.ssid!, payload.password ?? '');
        if (!saved) {
          _showError('The network wasn\'t saved. '
              'Join "${payload.ssid}" from Wi-Fi settings, then scan again.');
          return false;
        }
      case JoinFallbackAction.openSettings:
        // Best effort — the sheet already showed the password to type.
        await SystemSettings.openWifiSettings();
    }
    if (!mounted) return false;
    _probeCancelled = false;
    setState(() {
      _connecting = true;
      _probeWaiting = true;
      _progressLine = 'Waiting for this phone to reach ${payload.alias}…';
    });
    final reachable = await router.waitForReachable(
      payload,
      isCancelled: () => _probeCancelled || !mounted,
    );
    if (!mounted) return false;
    setState(() => _probeWaiting = false);
    if (_probeCancelled) {
      _clearPendingFallback(); // user opted out — don't nag on resume
      return false; // no error banner either
    }
    if (!reachable) {
      // Keep _pendingFallback: the user is likely still out in Settings —
      // resuming the app re-checks the target automatically (U3).
      _showError('Still can\'t reach "${payload.alias}". '
          'Join "${payload.ssid}" in Wi-Fi settings, then come back here.');
      return false;
    }
    _clearPendingFallback();
    setState(() => _progressLine = 'Reached ${payload.alias} — connecting…');
    return true;
  }

  void _clearPendingFallback() {
    _pendingFallback = null;
    _pendingRouter = null;
  }

  /// U3: on app resume with a pending Tier-2/3 target, briefly probe it
  /// ("Checking connection…"): reachable resumes the connect flow exactly
  /// as a successful join would; unreachable re-opens the fallback sheet
  /// with guidance instead of leaving a stale error on screen.
  Future<void> _recheckPendingFallback() async {
    final payload = _pendingFallback;
    final router = _pendingRouter;
    if (payload == null || router == null) return;
    // A connect / probe loop is already driving the UI — it owns the
    // outcome (the 90 s wait in _runJoinFallback keeps polling while the
    // user is out in Settings).
    if (_busy || _connecting || _probeWaiting || !mounted) return;
    final attempt = ++_attempt;
    setState(() {
      _connecting = true;
      _error = null;
      _retryAction = null;
      _progressLine = 'Checking connection…';
    });
    final reachable = await router.waitForReachable(
      payload,
      interval: const Duration(seconds: 1),
      overall: const Duration(seconds: 8),
      isCancelled: () => !mounted || attempt != _attempt,
    );
    if (!mounted || attempt != _attempt) return;
    setState(() {
      _connecting = false;
      _progressLine = null;
    });
    if (reachable) {
      _clearPendingFallback();
      await _connectToPayload(payload); // probes first → direct → redeem
      return;
    }
    final resumed = await _runJoinFallback(payload, router);
    if (!mounted) return;
    if (!resumed) {
      // No _onScannedRaw finally-block on this path — reset the progress
      // UI ourselves.
      setState(() {
        _connecting = false;
        _progressLine = null;
      });
      return;
    }
    _clearPendingFallback();
    await _connectToPayload(payload);
  }

  // ─── Connect path 3: Direct Link ─────────────────────────────────────

  Future<void> _connectDirect() async {
    final hostPort = _hostPortCtrl.text.trim();
    if (hostPort.isEmpty || _busy) return;
    if (AppState.looksLikeIpv6(hostPort)) {
      _showError("IPv6 addresses aren't supported yet. Use the IPv4 "
          'address shown on their Receive screen.');
      return;
    }
    setState(() {
      _busy = true;
      _connecting = true;
      _error = null;
    });
    try {
      final peer = await context.read<AppState>().probeManualPeer(hostPort);
      if (!mounted) return;
      setState(() => _connecting = false);
      if (peer == null) {
        _showError('No LanLink device answered at $hostPort. '
            'Check the address on their Receive screen.');
        return;
      }
      await _sendTo(peer);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _connecting = false;
        });
      }
    }
  }

  // ─── Staging + send ──────────────────────────────────────────────────

  Future<void> _sendTo(Device peer) async {
    // Guards the radar path against double-taps launching two pickers;
    // the QR/Direct Link paths already hold _busy and re-setting is a
    // harmless no-op.
    setState(() => _busy = true);
    try {
      final files = _staged.isNotEmpty ? _staged : await _pickFiles();
      if (files.isEmpty || !mounted) return;
      final state = context.read<AppState>();
      await state.sendFiles(peer: peer, files: files);
      // The session owns any joined hotspot network from here on; the
      // Disconnect path releases it via WifiJoiner.leave() (F1 contract).
      _handedOff = true;
      if (_joinedHotspot) state.markJoinedHotspotAsGuest();
      if (!mounted) return;
      // Back to home, where the session card shows live progress.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

  void _showError(String message, {VoidCallback? retry}) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _retryAction = retry;
      _progressLine = null;
    });
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
                  // Real discovery state (perf S3): the radar's spinner
                  // only animates while a sweep is actually in flight, so
                  // an idle screen stops repainting every frame.
                  searching: state.isScanning,
                  onPeerTap: (tapped) {
                    if (_busy) return;
                    // Resolve by fingerprint, never by display name:
                    // aliases collide (or can be spoofed), and the peer
                    // list mutates under a 6s discovery refresh. No match
                    // => the device left; never fall back to an arbitrary
                    // peer.
                    final peer = state.peers[tapped.id];
                    if (peer == null) {
                      _showError('That device just went offline. '
                          'Wait for it to reappear, then tap it again.');
                      return;
                    }
                    unawaited(_sendTo(peer));
                  },
                ),
                if (_connecting) ...[
                  const SizedBox(height: VSpace.x4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // RepaintBoundary: the looping spinner repaints every
                      // frame — keep that off the rest of the page's layer.
                      RepaintBoundary(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: VSpace.x3),
                      // Flexible: progress lines can be long (the Tier-1
                      // dialog guidance names the SSID) — wrap, don't
                      // overflow the row.
                      Flexible(
                        child: Text(
                          _progressLine ?? 'Connecting…',
                          textAlign: TextAlign.center,
                          style: VType.body
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  if (_probeWaiting || _joinWaiting) ...[
                    const SizedBox(height: VSpace.x2),
                    TextButton(
                      onPressed: () => setState(() {
                        _probeCancelled = true;
                        // U1: abandon the Tier-1 join wait — the racing
                        // Future.any in _connectToPayload surfaces the
                        // Tier-2/3 fallback sheet immediately.
                        if (!(_joinCancel?.isCompleted ?? true)) {
                          _joinCancel!.complete();
                        }
                      }),
                      child: const Text('Cancel'),
                    ),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: VSpace.x4),
                  Text(
                    _error!,
                    style: VType.body.copyWith(color: context.ember.danger),
                    textAlign: TextAlign.center,
                  ),
                  if (_retryAction != null) ...[
                    const SizedBox(height: VSpace.x2),
                    Center(
                      child: FilledButton.tonal(
                        onPressed: () {
                          final retry = _retryAction;
                          setState(() {
                            _retryAction = null;
                            _error = null;
                          });
                          retry?.call();
                        },
                        child: const Text('Retry'),
                      ),
                    ),
                  ],
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
