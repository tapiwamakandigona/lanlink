import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/discovery/connect_payload.dart';
import '../../state/app_state.dart';
import '../v4/direct_connect/hotspot_creds_panel.dart';
import '../v4/direct_connect/hotspot_host_controller.dart';
import '../v4/direct_connect/network_mode_switch.dart';
import '../v4/v4.dart';

/// Receive: shows the connect QR the instant it opens. The QR carries
/// host:port plus a one-time connect token; the local address is shown as
/// the Direct Link fallback for devices without a camera.
///
/// A two-option switch picks the network mode: "Same Wi-Fi" (today's LAN
/// flow) or "No shared Wi-Fi", which hosts an in-app LocalOnlyHotspot and
/// bakes its credentials into the QR so an Android guest auto-joins on
/// scan (iPhone/desktop guests get the SSID/password shown to join by
/// hand).
///
/// Connect tokens live in receiver memory only, so the payload (and QR) is
/// re-minted every time the app comes back to the foreground — a QR from
/// before a restart would carry a dead token.
class ReceivePage extends StatefulWidget {
  const ReceivePage({
    super.key,
    this.debugPayload,
    this.debugHotspotController,
  });

  /// Test hook: skips live state and renders exactly this payload
  /// (plus hotspot credentials when Direct link mode is running).
  final ConnectPayload? debugPayload;

  /// Test hook: injected hotspot controller with faked platform calls;
  /// also forces the "this platform can host" path on desktop test runs.
  final HotspotHostController? debugHotspotController;

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> with WidgetsBindingObserver {
  ConnectPayload? _payload;
  NetworkMode _mode = NetworkMode.sameWifi;
  HotspotHostController? _hotspot;

  /// The AppState we registered the hotspot stop path with (F3 Disconnect
  /// teardown hook), kept so dispose can unregister without touching
  /// context after deactivation.
  AppState? _teardownRegistrar;

  /// Only Android can host a LocalOnlyHotspot from inside an app.
  bool get _canHostDirectLink =>
      widget.debugHotspotController != null || Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mintPayload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _teardownRegistrar?.registerHotspotTeardown(null);
    _teardownRegistrar = null;
    final hotspot = _hotspot;
    if (hotspot != null) {
      hotspot.removeListener(_onHotspotChanged);
      if (widget.debugHotspotController == null) {
        // We own it: dispose stops any live reservation.
        hotspot.dispose();
      } else {
        // Injected by a test: tear down but let the test keep the object.
        unawaited(hotspot.disable());
      }
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    // Tokens are in-memory and single-use: regenerate whenever we resume so
    // the QR on screen is always redeemable.
    if (lifecycleState == AppLifecycleState.resumed) _mintPayload();
    // The engine is going away — never leave a hotspot reservation behind.
    if (lifecycleState == AppLifecycleState.detached) {
      unawaited(_hotspot?.disable());
    }
  }

  void _setMode(NetworkMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    if (mode == NetworkMode.directLink) {
      if (!_canHostDirectLink) return; // build shows the fallback pane
      final hotspot = _hotspot ??= (widget.debugHotspotController ??
          HotspotHostController())
        ..addListener(_onHotspotChanged);
      // F3 Disconnect teardown hook (F1 contract): while this device
      // hosts, AppState holds the stop path so Disconnect can tear the
      // hotspot down even though this page owns the controller.
      final appState = context.read<AppState>();
      appState.registerHotspotTeardown(hotspot.disable);
      _teardownRegistrar = appState;
      unawaited(hotspot.enable());
    } else {
      _teardownRegistrar?.registerHotspotTeardown(null);
      _teardownRegistrar = null;
      unawaited(_hotspot?.disable());
      _mintPayload();
    }
  }

  void _onHotspotChanged() {
    if (!mounted) return;
    // Credentials appeared (or went away) — refresh the QR payload.
    _mintPayload();
  }

  void _mintPayload() {
    final hotspot = _hotspot;
    final creds =
        _mode == NetworkMode.directLink && hotspot != null && hotspot.isRunning
            ? hotspot.info
            : null;
    if (widget.debugPayload != null) {
      final debug = widget.debugPayload!;
      setState(() {
        _payload = creds == null
            ? debug
            : ConnectPayload(
                ip: creds.hostIps.isNotEmpty ? creds.hostIps.first : debug.ip,
                port: debug.port,
                alias: debug.alias,
                fingerprint: debug.fingerprint,
                token: debug.token,
                ssid: creds.ssid,
                password: creds.password,
              );
      });
      return;
    }
    final state = context.read<AppState>();
    final port = state.port;
    // While hosting, prefer the hotspot interface address (192.168.49.x)
    // so joined guests reach us without a subnet scan.
    final ip = creds != null && creds.hostIps.isNotEmpty
        ? creds.hostIps.first
        : (state.localIps.isEmpty ? null : state.localIps.first);
    if (port == null || ip == null) {
      setState(() => _payload = null);
      return;
    }
    setState(() {
      _payload = ConnectPayload(
        ip: ip,
        port: port,
        alias: state.displayAlias,
        fingerprint: state.fingerprint,
        token: state.issueConnectToken(),
        ssid: creds?.ssid,
        password: creds?.password,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Narrow subscriptions (perf): this page only needs the display alias
    // and the "is the QR's token still valid" bit, so it selects those
    // instead of watching all of AppState — an unrelated notify (peer
    // announcements, session changes) no longer re-encodes the QR.
    final displayAlias =
        context.select<AppState, String>((s) => s.displayAlias);
    final payload = _payload;
    // Tokens are single-use: the moment a sender redeems the displayed
    // one, re-mint so the QR on screen is always valid (a second device
    // can scan right away).
    final token = payload?.token;
    final tokenStale = context.select<AppState, bool>((s) =>
        widget.debugPayload == null &&
        token != null &&
        !s.isConnectTokenValid(token));
    if (tokenStale) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = context.read<AppState>();
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NetworkModeSwitch(mode: _mode, onChanged: _setMode),
                  const SizedBox(height: VSpace.x5),
                  ..._buildBody(scheme, displayAlias, payload),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody(
    ColorScheme scheme,
    String displayAlias,
    ConnectPayload? payload,
  ) {
    if (_mode == NetworkMode.directLink) {
      if (!_canHostDirectLink) return [_DirectLinkUnsupported(scheme: scheme)];
      final hotspot = _hotspot;
      switch (hotspot?.phase ?? HotspotHostPhase.idle) {
        case HotspotHostPhase.idle:
        case HotspotHostPhase.checking:
        case HotspotHostPhase.starting:
          return [_ProgressLine(scheme: scheme, text: 'Starting your link…')];
        case HotspotHostPhase.needsPermission:
          return [
            _MessagePane(
              scheme: scheme,
              icon: Icons.wifi_tethering,
              title: 'One quick permission',
              body: 'Android asks for a nearby-devices (or location) '
                  'permission before an app may create a hotspot. LanLink '
                  'uses it only for that.',
              actionLabel: 'Allow and continue',
              onAction: () => unawaited(hotspot!.grantPermission()),
            ),
          ];
        case HotspotHostPhase.failed:
          return [
            _MessagePane(
              scheme: scheme,
              icon: Icons.error_outline,
              title: "Couldn't start the link",
              body: hotspot?.error ?? 'Unknown error.',
              actionLabel: 'Try again',
              onAction: () => unawaited(hotspot!.enable()),
            ),
          ];
        case HotspotHostPhase.running:
          final info = hotspot!.info!;
          return [
            if (payload == null)
              _Unavailable(scheme: scheme, onRetry: _mintPayload)
            else ...[
              QrDisplayPanel(
                payload: payload.toQrString(),
                deviceName: displayAlias,
              ),
              const SizedBox(height: VSpace.x3),
              Text(
                'They scan, their phone hops onto your link — done.',
                style: VType.caption.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: VSpace.x5),
              HotspotCredsPanel(ssid: info.ssid, password: info.password),
            ],
          ];
      }
    }
    // Same Wi-Fi (default): today's flow, unchanged.
    return [
      if (payload == null)
        _Unavailable(scheme: scheme, onRetry: _mintPayload)
      else ...[
        QrDisplayPanel(
          payload: payload.toQrString(),
          deviceName: displayAlias,
        ),
        const SizedBox(height: VSpace.x6),
        Text(
          'No camera on the other device? Use Direct Link with this '
          'address:',
          style: VType.label.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: VSpace.x2),
        // Tap-to-copy: reading an IP:port off one screen and typing it
        // on another is exactly the sort of friction a copy chip removes
        // (desktop peers can paste into Direct Link).
        Center(
          child: ActionChip(
            avatar: Icon(Icons.copy, size: 16, color: scheme.onSurface),
            label: Text(
              payload.hostPort,
              style: VType.bodyStrong.copyWith(color: scheme.onSurface),
            ),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: payload.hostPort));
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(
                  content: Text('Address copied'),
                  duration: Duration(seconds: 2),
                ));
            },
          ),
        ),
      ],
    ];
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.scheme, required this.text});

  final ColorScheme scheme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VSpace.x8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // RepaintBoundary: the looping spinner repaints every frame —
          // keep that off the rest of the page's layer.
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
          Text(text,
              style: VType.body.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _MessagePane extends StatelessWidget {
  const _MessagePane({
    required this.scheme,
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final ColorScheme scheme;
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 40, color: scheme.onSurfaceVariant),
        const SizedBox(height: VSpace.x4),
        Text(
          title,
          style: VType.heading.copyWith(color: scheme.onSurface),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: VSpace.x2),
        Text(
          body,
          style: VType.body.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: VSpace.x5),
        FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

/// Shown when the user flips to "No shared Wi-Fi" on a platform that
/// can't host an in-app hotspot (everything except Android).
class _DirectLinkUnsupported extends StatelessWidget {
  const _DirectLinkUnsupported({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.wifi_tethering_off,
            size: 40, color: scheme.onSurfaceVariant),
        const SizedBox(height: VSpace.x4),
        Text(
          'Direct link needs an Android host',
          style: VType.heading.copyWith(color: scheme.onSurface),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: VSpace.x2),
        Text(
          'Only Android can open a hotspot from inside an app. Start the '
          'direct link on the Android device instead, or get both devices '
          'onto the same Wi-Fi.',
          style: VType.body.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
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
