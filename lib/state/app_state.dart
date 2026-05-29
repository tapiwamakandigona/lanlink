import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/connectivity/connectivity_mode.dart';
import '../core/discovery/multicast_discovery.dart';
import '../core/discovery/subnet_scanner.dart';
import '../core/history/transfer_history_store.dart';
import '../core/update/update_checker.dart';
import '../core/models/device.dart';
import '../core/models/file_info.dart';
import '../core/models/session.dart';
import '../core/platform/foreground_service.dart';
import '../core/platform/platform_share.dart';
import '../core/platform/transfer_notifications.dart';
import '../core/protocol/constants.dart';
import '../core/settings/app_settings.dart';
import '../core/transfer/receiver.dart';
import '../core/transfer/sender.dart';
import '../core/util/event_log.dart';
import '../core/util/fingerprint.dart';
import '../core/util/network.dart';

/// Signature for the UI hook that asks the user whether to accept an
/// incoming transfer. The UI is expected to show a modal and return when
/// the user has accepted or declined.
typedef IncomingTransferPrompt = Future<AcceptDecision> Function(
  Device peer,
  List<FileInfo> files,
);

/// Top-level state container. Owns the [Receiver], [Sender], discovery
/// service, and lists of peers + sessions. UI components subscribe to this
/// via Provider.
class AppState extends ChangeNotifier {
  AppState._({
    required this.settings,
    required String fingerprint,
    required List<String> localIps,
  })  : _fingerprint = fingerprint,
        _localIps = localIps;

  final AppSettings settings;
  final String _fingerprint;
  final List<String> _localIps;

  late Receiver _receiver;
  late Sender _sender;
  late MulticastDiscovery _discovery;
  late SubnetScanner _subnetScanner;
  late UpdateChecker _updateChecker;
  late TransferHistoryStore _history;

  /// Whether a manual / automatic subnet sweep is currently in flight.
  bool _scanning = false;
  bool get isScanning => _scanning;

  UpdateChecker get updateChecker => _updateChecker;

  /// UI hook installed by main.dart once the navigator is alive.
  IncomingTransferPrompt? _incomingPrompt;

  /// Map of peer fingerprint -> Device. Latest announcement wins.
  final Map<String, Device> _peers = {};
  Map<String, Device> get peers => Map.unmodifiable(_peers);

  /// In-progress and finished sessions, newest first.
  final List<TransferSession> _sessions = [];
  List<TransferSession> get sessions => List.unmodifiable(_sessions);

  /// Local listening port (may differ from settings if it was in use).
  int? get port => _receiver.port;

  /// IPv4 addresses we're listening on (for the Settings screen).
  List<String> get localIps => List.unmodifiable(_localIps);

  String get fingerprint => _fingerprint;

  /// Initializes everything: loads settings, picks a fingerprint, starts
  /// the HTTP server, and starts UDP discovery.
  static Future<AppState> bootstrap() async {
    final settings = await AppSettings.load();
    // Materialise the platform-aware connectivity default (Hotspot on
    // Android, LAN elsewhere) once per install before any UI reads it.
    await settings.ensureConnectivityDefault();
    final fingerprint = await loadOrCreateFingerprint();
    final ips = await listLocalIPv4Addresses();
    final state = AppState._(
      settings: settings,
      fingerprint: fingerprint,
      localIps: ips,
    );
    state._history = await TransferHistoryStore.getInstance();
    state._sessions.addAll(state._history.load());

    state._receiver = Receiver(
      localDeviceProvider: state._buildSelfDevice,
      saveDirProvider: state._resolveSaveDir,
      onAccept: state._handleIncomingPrompt,
      onSessionStarted: state._handleNewReceiveSession,
    );
    state._sender = Sender(localDeviceProvider: state._buildSelfDevice);
    state._discovery = MulticastDiscovery(
      selfDevice: state._buildSelfDevice(),
      onPeer: state._onPeerSeen,
    );
    state._subnetScanner = SubnetScanner(
      sender: state._sender,
      onPeer: state._onPeerSeen,
    );
    state._updateChecker = UpdateChecker();
    state._updateChecker.addListener(state.notifyListeners);

    settings.addListener(state._onSettingsChanged);

    await state._receiver.start();
    EventLog.instance.add(
      'Receiver listening on ${ips.join(", ")}:${state._receiver.port}',
    );
    await state._discovery.start();
    if (settings.connectivityMode == ConnectivityMode.hotspot) {
      unawaited(state._kickSubnetScan());
    }
    if (settings.autoUpdateCheck) {
      unawaited(state._updateChecker.initialize());
    }
    return state;
  }

  /// Detects which side of a hotspot we are on based on the local IPs.
  /// `HotspotRole.auto` is replaced with the best guess; the explicit
  /// settings override always wins.
  HotspotRole resolveHotspotRole() {
    final explicit = settings.hotspotRole;
    if (explicit != HotspotRole.auto) return explicit;
    for (final ip in _localIps) {
      if (_looksLikeHotspotGateway(ip)) return HotspotRole.hosting;
    }
    return HotspotRole.joining;
  }

  static bool _looksLikeHotspotGateway(String ip) {
    const gateways = <String>{
      '192.168.43.1',
      '192.168.49.1',
      '192.168.1.1',
      '10.0.0.1',
      '172.20.10.1',
    };
    return gateways.contains(ip);
  }

  /// Pokes multicast announce and kicks off a fresh subnet sweep. Wired to
  /// the refresh button in the home page and the mode-switch handler so
  /// changing modes immediately rediscovers peers.
  Future<void> refreshDiscovery() async {
    _discovery.poke();
    final ips = await listLocalIPv4Addresses();
    _localIps
      ..clear()
      ..addAll(ips);
    if (settings.connectivityMode == ConnectivityMode.hotspot ||
        settings.connectivityMode == ConnectivityMode.lan) {
      await _kickSubnetScan();
    }
  }

  Future<void> _kickSubnetScan() async {
    if (_scanning) {
      _subnetScanner.cancel();
    }
    _scanning = true;
    notifyListeners();
    try {
      await _subnetScanner.scan(localIps: _localIps);
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  void installIncomingPrompt(IncomingTransferPrompt prompt) {
    _incomingPrompt = prompt;
  }

  /// Builds the Device payload representing this install.
  Device _buildSelfDevice() {
    final alias =
        settings.alias.trim().isEmpty ? _defaultAlias() : settings.alias.trim();
    return Device(
      alias: alias,
      version: LanLinkProtocol.protocolVersion,
      deviceModel: detectDeviceModel(),
      deviceType: detectDeviceType(),
      fingerprint: _fingerprint,
      port: _receiver.port ?? settings.port,
      protocol: 'http',
      ip: _localIps.isEmpty ? '0.0.0.0' : _localIps.first,
    );
  }

  String _defaultAlias() {
    if (Platform.isAndroid) return 'Android device';
    if (Platform.isIOS) return 'iOS device';
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'LanLink device';
    }
  }

  Future<Directory> _resolveSaveDir() async {
    // Android always writes to the app's private external files dir first;
    // the receiver then republishes the finished file into the user-visible
    // Downloads/LanLink MediaStore collection. Custom save folders picked
    // through the Storage Access Framework would come back as `content://`
    // URIs that dart:io can't open directly, so we deliberately ignore
    // settings.saveDir on Android and route everything through MediaStore.
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        return Directory(p.join(dir.path, 'LanLink', 'incoming'));
      }
      // Last-ditch fallback (very old devices): app documents dir.
      final docs = await getApplicationDocumentsDirectory();
      return Directory(p.join(docs.path, 'LanLink'));
    }

    // Desktop platforms: honour the user-picked folder if it's set.
    final fromSettings = settings.saveDir;
    if (fromSettings != null && fromSettings.isNotEmpty) {
      return Directory(fromSettings);
    }
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return Directory(p.join(downloads.path, 'LanLink'));
      }
    } catch (_) {}
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'LanLink'));
  }

  Future<AcceptDecision> _handleIncomingPrompt(
      Device peer, List<FileInfo> files) async {
    // Trusted peer with quick-save => auto-accept.
    if (settings.quickSave &&
        settings.trustedFingerprints.contains(peer.fingerprint)) {
      return AcceptDecision.accept(files.map((f) => f.id).toSet());
    }
    final prompt = _incomingPrompt;
    if (prompt == null) {
      // If the UI isn't ready, reject by default — the sender can retry.
      return AcceptDecision.reject();
    }
    return prompt(peer, files);
  }

  void _handleNewReceiveSession(TransferSession session) {
    EventLog.instance.add(
      'Incoming transfer from ${session.peer.alias} '
      '(${session.files.length} file(s))',
    );
    _sessions.insert(0, session);
    notifyListeners();
    _attachNotifications(session);
    _attachHistoryPersistence(session);
    _attachForegroundLifecycle(session);
    session.addListener(() => notifyListeners());
    _refreshForegroundService();
  }

  /// Hooks a session into the Android foreground service so the OS keeps
  /// our process alive while the user backgrounds the app mid-transfer.
  /// The actual start / stop call lives in [_refreshForegroundService];
  /// this just makes sure status transitions re-evaluate it.
  void _attachForegroundLifecycle(TransferSession session) {
    var hasFiredTerminal = false;
    void onChange() {
      switch (session.status) {
        case TransferStatus.completed:
        case TransferStatus.failed:
        case TransferStatus.cancelled:
          if (hasFiredTerminal) return;
          hasFiredTerminal = true;
          _refreshForegroundService();
        case TransferStatus.awaitingAccept:
        case TransferStatus.transferring:
          return;
      }
    }

    session.addListener(onChange);
  }

  /// Counts active (non-terminal) sessions and (re)reconciles the Android
  /// foreground service. The bridge itself is a no-op on non-Android
  /// platforms so we can call it unconditionally.
  void _refreshForegroundService() {
    final active = _sessions.where((s) {
      switch (s.status) {
        case TransferStatus.awaitingAccept:
        case TransferStatus.transferring:
          return true;
        case TransferStatus.completed:
        case TransferStatus.failed:
        case TransferStatus.cancelled:
          return false;
      }
    }).length;
    unawaited(TransferForegroundService.instance.sync(active));
  }

  /// Wires a session to the history store so it gets persisted as soon as
  /// it reaches a terminal status (`completed`, `failed`, or `cancelled`).
  /// Each lifecycle change triggers a debounced save of the full session
  /// list so the on-disk copy always reflects the latest state.
  void _attachHistoryPersistence(TransferSession session) {
    var saved = false;
    void onChange() {
      switch (session.status) {
        case TransferStatus.completed:
        case TransferStatus.failed:
        case TransferStatus.cancelled:
          if (saved) return;
          saved = true;
          _history.scheduleSave(_sessions);
        case TransferStatus.awaitingAccept:
        case TransferStatus.transferring:
          return;
      }
    }

    session.addListener(onChange);
  }

  /// Wipe persisted history and drop any finished sessions from memory.
  Future<void> clearHistory() async {
    await _history.clear();
    _sessions.removeWhere((s) {
      switch (s.status) {
        case TransferStatus.completed:
        case TransferStatus.failed:
        case TransferStatus.cancelled:
          return true;
        case TransferStatus.awaitingAccept:
        case TransferStatus.transferring:
          return false;
      }
    });
    notifyListeners();
  }

  /// Wires the system notification helper to a session's lifecycle. The
  /// receive side always gets notifications (so the user can see incoming
  /// transfers without the app in the foreground); the send side gets them
  /// too so they don't ghost away into the background. Each notification
  /// is keyed by `session.sessionId` so updates collapse onto a single row.
  void _attachNotifications(TransferSession session) {
    if (!TransferNotifications.instance.isSupported) return;
    final notifications = TransferNotifications.instance;
    unawaited(notifications.ensurePermission());
    var done = false;
    // Throttle updates so we don't slam the system NotificationManager.
    DateTime lastPosted = DateTime.fromMillisecondsSinceEpoch(0);
    unawaited(notifications.showProgress(session));
    session.addListener(() {
      if (done) return;
      switch (session.status) {
        case TransferStatus.completed:
        case TransferStatus.failed:
        case TransferStatus.cancelled:
          done = true;
          unawaited(notifications.showFinal(session));
          return;
        case TransferStatus.awaitingAccept:
        case TransferStatus.transferring:
          final now = DateTime.now();
          if (now.difference(lastPosted).inMilliseconds < 250) return;
          lastPosted = now;
          unawaited(notifications.showProgress(session));
      }
    });
  }

  void _onPeerSeen(Device peer) {
    if (peer.fingerprint == _fingerprint) return;
    final existing = _peers[peer.fingerprint];
    _peers[peer.fingerprint] = peer;
    if (existing == null || existing.alias != peer.alias) {
      notifyListeners();
    } else {
      // Even when nothing visible changed we still notify on a debounced
      // boundary so "last seen" indicators (future feature) can update.
      notifyListeners();
    }
  }

  void _onSettingsChanged() {
    _discovery.selfDevice = _buildSelfDevice();
    _discovery.poke();
    if (settings.connectivityMode == ConnectivityMode.hotspot && !_scanning) {
      unawaited(_kickSubnetScan());
    }
    notifyListeners();
  }

  /// Initiates a send to [peer]. Returns the live [TransferSession] that the
  /// caller (and any subscribed UI) can listen to for progress.
  ///
  /// The returned session is the same object the sender mutates throughout
  /// the transfer, so per-file byte counters and the overall status are
  /// visible immediately as bytes leave the socket.
  Future<TransferSession> sendFiles({
    required Device peer,
    required List<FileInfo> files,
  }) async {
    if (settings.connectivityMode == ConnectivityMode.bluetooth) {
      return _sendFilesOverBluetooth(peer: peer, files: files);
    }
    final session = TransferSession(
      sessionId: 'sending-${DateTime.now().microsecondsSinceEpoch}',
      direction: TransferDirection.send,
      peer: peer,
      files: {
        for (final f in files)
          f.id: FileProgress(file: f, status: TransferStatus.transferring),
      },
      status: TransferStatus.transferring,
    );
    _sessions.insert(0, session);
    session.addListener(() => notifyListeners());
    _attachNotifications(session);
    _attachHistoryPersistence(session);
    _attachForegroundLifecycle(session);
    _attachOutcomeLog(session, peer.alias);
    notifyListeners();
    _refreshForegroundService();

    EventLog.instance.add('Sending ${files.length} file(s) to ${peer.alias}');

    // Drive the transfer in the background. The sender mutates `session`
    // directly so we don't have to swap anything in the list afterward.
    unawaited(_sender.send(session: session, peer: peer, files: files));

    return session;
  }

  /// Records the terminal outcome of [session] to the diagnostics log.
  void _attachOutcomeLog(TransferSession session, String peerAlias) {
    var logged = false;
    session.addListener(() {
      if (logged) return;
      switch (session.status) {
        case TransferStatus.completed:
          logged = true;
          EventLog.instance.add('Transfer to $peerAlias completed');
        case TransferStatus.failed:
          logged = true;
          EventLog.instance
              .add('Transfer to $peerAlias failed', level: EventLevel.error);
        case TransferStatus.cancelled:
          logged = true;
          EventLog.instance
              .add('Transfer to $peerAlias cancelled', level: EventLevel.warn);
        case TransferStatus.awaitingAccept:
        case TransferStatus.transferring:
          return;
      }
    });
  }

  Future<TransferSession> _sendFilesOverBluetooth({
    required Device peer,
    required List<FileInfo> files,
  }) async {
    final session = TransferSession(
      sessionId: 'bluetooth-${DateTime.now().microsecondsSinceEpoch}',
      direction: TransferDirection.send,
      peer: peer,
      files: {
        for (final f in files)
          f.id: FileProgress(file: f, status: TransferStatus.awaitingAccept),
      },
      status: TransferStatus.awaitingAccept,
    );
    _sessions.insert(0, session);
    session.addListener(() => notifyListeners());
    _attachNotifications(session);
    _attachHistoryPersistence(session);
    _attachForegroundLifecycle(session);
    notifyListeners();
    _refreshForegroundService();

    final paths = files
        .map((file) => file.localPath)
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList();
    final shared = await PlatformShare.shareViaBluetooth(paths: paths);
    if (shared) {
      for (final file in files) {
        session.markFile(file.id, TransferStatus.completed);
      }
      session.markStatus(TransferStatus.completed);
    } else {
      for (final file in files) {
        session.markFile(
          file.id,
          TransferStatus.failed,
          error: 'Bluetooth sharing is unavailable on this device.',
        );
      }
      session.markStatus(TransferStatus.failed);
    }
    return session;
  }

  /// Sends the same staged files to multiple peers in parallel. Each peer
  /// gets its own [TransferSession] (and its own progress card in the UI) —
  /// the upload is not actually de-duplicated on the wire, so this is just
  /// a convenience over calling [sendFiles] in a loop. Bluetooth peers are
  /// silently filtered out because [_sendFilesOverBluetooth] runs through
  /// the system share sheet which can only target one device per chooser.
  Future<List<TransferSession>> sendFilesToMany({
    required List<Device> peers,
    required List<FileInfo> files,
  }) async {
    final lan = peers
        .where((p) =>
            p.fingerprint != _fingerprint &&
            (p.protocol.isEmpty || p.protocol != 'bluetooth'))
        .toList();
    final sessions = <TransferSession>[];
    for (final peer in lan) {
      final session = await sendFiles(peer: peer, files: files);
      sessions.add(session);
    }
    return sessions;
  }

  /// Whether [session] can be retried: it must be an outgoing send that
  /// ended in a non-success state and still has at least one source file we
  /// can read off disk.
  static bool canRetry(TransferSession session) {
    if (session.direction != TransferDirection.send) return false;
    if (session.status != TransferStatus.failed &&
        session.status != TransferStatus.cancelled) {
      return false;
    }
    return session.files.values.any(
      (p) => (p.file.localPath ?? '').isNotEmpty,
    );
  }

  /// Re-stages the files from a failed/cancelled send [session] and sends
  /// them to the same peer again. Returns the fresh [TransferSession], or
  /// null when none of the original files are still available on disk.
  Future<TransferSession?> retrySession(TransferSession session) async {
    if (session.direction != TransferDirection.send) return null;
    final files = session.files.values
        .map((p) => p.file)
        .where((f) => (f.localPath ?? '').isNotEmpty)
        .toList();
    if (files.isEmpty) return null;
    EventLog.instance.add(
      'Retrying send of ${files.length} file(s) to ${session.peer.alias}',
    );
    return sendFiles(peer: session.peer, files: files);
  }

  /// Manually adds a peer by host:port. Useful when discovery is blocked.
  Future<Device?> probeManualPeer(String hostPort) async {
    final parts = hostPort.split(':');
    if (parts.isEmpty) return null;
    final host = parts[0];
    final port = parts.length > 1
        ? int.tryParse(parts[1]) ?? LanLinkProtocol.defaultPort
        : LanLinkProtocol.defaultPort;
    final stub = Device(
      alias: host,
      version: LanLinkProtocol.protocolVersion,
      deviceModel: '',
      deviceType: LanLinkProtocol.deviceTypeHeadless,
      fingerprint: '',
      port: port,
      protocol: 'http',
      ip: host,
    );
    final probed = await _sender.probe(stub);
    if (probed != null) _onPeerSeen(probed);
    return probed;
  }

  @override
  void dispose() {
    settings.removeListener(_onSettingsChanged);
    _updateChecker.removeListener(notifyListeners);
    _updateChecker.dispose();
    _subnetScanner.cancel();
    _discovery.stop();
    _receiver.stop();
    super.dispose();
  }
}
