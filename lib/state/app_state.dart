import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/connectivity/connectivity_mode.dart';
import '../core/discovery/multicast_discovery.dart';
import '../core/models/device.dart';
import '../core/models/file_info.dart';
import '../core/models/session.dart';
import '../core/platform/platform_share.dart';
import '../core/protocol/constants.dart';
import '../core/settings/app_settings.dart';
import '../core/transfer/receiver.dart';
import '../core/transfer/sender.dart';
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
    final fingerprint = await loadOrCreateFingerprint();
    final ips = await listLocalIPv4Addresses();
    final state = AppState._(
      settings: settings,
      fingerprint: fingerprint,
      localIps: ips,
    );

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

    settings.addListener(state._onSettingsChanged);

    await state._receiver.start();
    await state._discovery.start();
    return state;
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
    final fromSettings = settings.saveDir;
    if (fromSettings != null && fromSettings.isNotEmpty) {
      return Directory(fromSettings);
    }
    // Fall back to per-platform sensible defaults.
    if (Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download/LanLink');
      try {
        await downloads.create(recursive: true);
        return downloads;
      } catch (_) {
        final dir = await getExternalStorageDirectory();
        if (dir != null) return Directory(p.join(dir.path, 'LanLink'));
      }
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
    _sessions.insert(0, session);
    notifyListeners();
    session.addListener(() => notifyListeners());
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
    notifyListeners();
  }

  /// Initiates a send to [peer]. Returns the live [TransferSession].
  Future<TransferSession> sendFiles({
    required Device peer,
    required List<FileInfo> files,
  }) async {
    if (settings.connectivityMode == ConnectivityMode.bluetooth) {
      return _sendFilesOverBluetooth(peer: peer, files: files);
    }
    final placeholder = TransferSession(
      sessionId: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      direction: TransferDirection.send,
      peer: peer,
      files: {
        for (final f in files)
          f.id: FileProgress(file: f, status: TransferStatus.transferring),
      },
      status: TransferStatus.transferring,
    );
    _sessions.insert(0, placeholder);
    placeholder.addListener(() => notifyListeners());
    notifyListeners();

    // Kick off the actual send in the background; replace the placeholder
    // entry with the real session once we have the server-assigned ID.
    unawaited(() async {
      final real = await _sender.send(peer: peer, files: files);
      final idx = _sessions.indexOf(placeholder);
      if (idx >= 0) {
        _sessions[idx] = real;
        real.addListener(() => notifyListeners());
        notifyListeners();
      } else {
        _sessions.insert(0, real);
        real.addListener(() => notifyListeners());
        notifyListeners();
      }
    }());

    return placeholder;
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
    notifyListeners();

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
    _discovery.stop();
    _receiver.stop();
    super.dispose();
  }
}
