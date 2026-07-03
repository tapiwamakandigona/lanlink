// F3 "Bidirectional sessions + Disconnect/Unpair" behavior tests.
//
// Two REAL peer instances run side by side (loopback Receivers + Senders —
// the exact classes the app ships), each fronted by its own AppState:
//  * pairing via a one-time connect token links + pins BOTH sides, so the
//    receiver can send back without re-scanning;
//  * Disconnect clears links/pins on both sides and the disconnected peer's
//    further pushes are rejected server-side (403) until it re-pairs;
//  * the /disconnect route itself is bounded (413 on oversized bodies) and
//    only honoured for linked peers (403 for strangers);
//  * Disconnect runs the registered Direct Connect teardown hook;
//  * perf regression: a session's progress ticks do NOT fan out into
//    AppState.notifyListeners (only status transitions do).

import 'tls_test_helpers.dart';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/security/device_certificate.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'e2e_sim/e2e_helpers.dart';

/// One full app-side peer: settings + AppState + a live loopback Receiver
/// wired through the same debug hooks the app shell uses.
class _Peer {
  _Peer(this.name, this.cert);

  final String name;
  final DeviceCertificate cert;

  /// Protocol 2.1: a peer's fingerprint IS its TLS cert hash.
  String get fingerprint => cert.fingerprint;
  late final AppSettings settings;
  late final AppState state;
  late final Receiver receiver;
  late final Directory saveDir;
  int get port => receiver.port!;

  Device get self => device(name, fingerprint, port);

  Future<void> start() async {
    saveDir = await Directory.systemTemp.createTemp('lanlink_bidi_$name');
    settings = await AppSettings.load();
    state = AppState.forScreenshots(settings: settings);
    receiver = Receiver(
      certificateProvider: () async => cert,
      // `receiver.port` is null until the server binds; 0 asks the OS for
      // an ephemeral port on first bind, afterwards it self-describes.
      localDeviceProvider: () => device(name, fingerprint, receiver.port ?? 0),
      saveDirProvider: () async => saveDir,
      onAccept: (peer, files) async =>
          AcceptDecision.accept(files.map((f) => f.id).toSet()),
      onSessionStarted: (_) {},
    );
    await receiver.start();
    // Same wiring as AppState.bootstrap: links redeemed callers back,
    // honours /disconnect only for linked peers, blocks disconnected ones.
    state.debugInstallReceiver(receiver);
    state.debugInstallSender(Sender(localDeviceProvider: () => self));
  }

  Future<void> stop() async {
    await receiver.stop();
    try {
      await saveDir.delete(recursive: true);
    } catch (_) {}
  }
}

void main() {
  late _Peer a;
  late _Peer b;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    a = _Peer('alice', testCertificate());
    await a.start();
    // Fresh prefs per state; AppSettings.load reads the same mock store but
    // pin/trust sets are keyed identically — reset between peers so each
    // side starts clean. (Both states share the mock store; assertions
    // below always check via each side's own settings handle.)
    b = _Peer('bob', testCertificateB());
    await b.start();
  });

  tearDown(() async {
    await a.stop();
    await b.stop();
  });

  Future<Device?> pair() => a.state
      .connectWithToken('127.0.0.1:${b.port}', b.receiver.issueConnectToken());

  test('token pairing links and pins BOTH sides (symmetric trust)', () async {
    final peerB = await pair();
    expect(peerB, isNotNull);
    expect(peerB!.fingerprint, b.fingerprint);

    // A side: linked + pinned (as before).
    expect(a.state.isLinked(b.fingerprint), isTrue);
    expect(a.settings.isPinned(b.fingerprint), isTrue);

    // B side: the receiver linked + pinned the caller back — no re-scan
    // needed to send in the other direction.
    await waitFor(() => b.state.isLinked(a.fingerprint));
    await waitFor(() => b.settings.isPinned(a.fingerprint));
    final linkedBack = b.state.linkedPeers.single;
    expect(linkedBack.fingerprint, a.fingerprint);
    expect(linkedBack.ip, '127.0.0.1');
    expect(linkedBack.port, a.port, reason: 'B must be able to dial A back');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
      'B sends a file back to A without re-scanning, then either side '
      'disconnects and pushes are rejected server-side until re-pair',
      () async {
    await pair();
    await waitFor(() => b.state.isLinked(a.fingerprint));

    // A -> B.
    final tmp = await Directory.systemTemp.createTemp('lanlink_bidi_files');
    addTearDown(() => tmp.delete(recursive: true));
    final f1 =
        await writeDeterministicFile('${tmp.path}/a_to_b.bin', 64 * 1024);
    final s1 = await a.state.sendFiles(
      peer: a.state.linkedPeers.single,
      files: [fileInfoFor(f1, fileName: 'a_to_b.bin', size: 64 * 1024)],
    );
    await waitFor(() => s1.isTerminal);
    expect(s1.status, TransferStatus.completed);

    // B -> A, dialing the link learned at pairing time — no scan, no QR.
    final f2 = await writeDeterministicFile('${tmp.path}/b_to_a.bin', 64 * 1024,
        seed: 23);
    final s2 = await b.state.sendFiles(
      peer: b.state.linkedPeers.single,
      files: [fileInfoFor(f2, fileName: 'b_to_a.bin', size: 64 * 1024)],
    );
    await waitFor(() => s2.isTerminal);
    expect(s2.status, TransferStatus.completed);
    expect(
      File('${a.saveDir.path}/b_to_a.bin').existsSync() ||
          a.saveDir.listSync().whereType<File>().isNotEmpty,
      isTrue,
      reason: 'the send-back must land in A\'s save dir',
    );

    // B disconnects; A is notified over /disconnect and clears too.
    await b.state.disconnectPeer(b.state.linkedPeers.single);
    expect(b.state.isLinked(a.fingerprint), isFalse);
    expect(b.state.isPeerDisconnected(a.fingerprint), isTrue);
    expect(b.settings.isPinned(a.fingerprint), isFalse,
        reason: 'unpair clears pin');
    await waitFor(() => !a.state.isLinked(b.fingerprint));
    await waitFor(() => a.state.isPeerDisconnected(b.fingerprint));

    // Server-side enforcement: A's push to B is rejected before any prompt.
    final dio = trustAllDio(BaseOptions(validateStatus: (_) => true));
    final resp = await dio.post<String>(
      'https://127.0.0.1:${b.port}${LanLinkProtocol.routePrepareUpload}',
      data: {
        'info': a.self.toJson(),
        'files': {
          'x1': FileInfo(
            id: 'x1',
            fileName: 'nope.bin',
            size: 10,
            fileType: 'other',
          ).toJson(),
        },
      },
    );
    expect(resp.statusCode, 403,
        reason: 'a disconnected peer cannot push files until it re-pairs');

    // Re-pair with a fresh token: link restored, pushes flow again.
    final again = await pair();
    expect(again, isNotNull);
    expect(a.state.isPeerDisconnected(b.fingerprint), isFalse);
    await waitFor(() => b.state.isLinked(a.fingerprint));
    expect(b.state.isPeerDisconnected(a.fingerprint), isFalse);
    final f3 = await writeDeterministicFile('${tmp.path}/again.bin', 4 * 1024,
        seed: 5);
    final s3 = await a.state.sendFiles(
      peer: a.state.linkedPeers.single,
      files: [fileInfoFor(f3, fileName: 'again.bin', size: 4 * 1024)],
    );
    await waitFor(() => s3.isTerminal);
    expect(s3.status, TransferStatus.completed);
  }, timeout: const Timeout(Duration(seconds: 60)));

  group('/disconnect route hardening', () {
    test('stranger (unlinked fingerprint) gets 403 and tears nothing down',
        () async {
      await pair();
      await waitFor(() => b.state.isLinked(a.fingerprint));
      final dio = trustAllDio(BaseOptions(validateStatus: (_) => true));
      final resp = await dio.post<String>(
        'https://127.0.0.1:${b.port}${LanLinkProtocol.routeDisconnect}',
        data: device('evil', 'fp-evil', 999).toJson(),
      );
      expect(resp.statusCode, 403);
      expect(b.state.isLinked(a.fingerprint), isTrue,
          reason: 'a stranger must not end someone else\'s session');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('oversized body is rejected (bounded control route)', () async {
      final dio = trustAllDio(BaseOptions(validateStatus: (_) => true));
      int? status;
      try {
        final resp = await dio.post<String>(
          'https://127.0.0.1:${b.port}${LanLinkProtocol.routeDisconnect}',
          data: '{"padding": "${'A' * (65 * 1024)}"}',
          options: Options(contentType: 'application/json'),
        );
        status = resp.statusCode;
      } on DioException {
        status = null; // connection aborted mid-body is also acceptable
      }
      expect(status, anyOf(isNull, 413),
          reason: '/disconnect must use the bounded-body helpers');
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('missing device info is a 400', () async {
      final dio = trustAllDio(BaseOptions(validateStatus: (_) => true));
      final resp = await dio.post<String>(
        'https://127.0.0.1:${b.port}${LanLinkProtocol.routeDisconnect}',
        data: jsonEncode({'not': 'a device'}),
        options: Options(contentType: 'application/json'),
      );
      expect(resp.statusCode, 400);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  test('disconnect runs the registered Direct Connect teardown hook', () async {
    await pair();
    var hostTeardowns = 0;
    a.state.registerHotspotTeardown(() async => hostTeardowns++);
    await a.state.disconnectPeer(a.state.linkedPeers.single);
    expect(hostTeardowns, 1,
        reason: 'a hosted hotspot must be stopped on Disconnect');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
      'adopted hotspot (accept → home handoff) is stopped AND disposed on '
      'Disconnect', () async {
    await pair();
    var teardowns = 0;
    var disposes = 0;
    a.state.adoptHotspot(
      teardown: () async => teardowns++,
      dispose: () => disposes++,
    );
    await a.state.disconnectPeer(a.state.linkedPeers.single);
    expect(teardowns, 1,
        reason: 'the adopted hotspot must be stopped on Disconnect');
    expect(disposes, 1,
        reason: 'AppState owns the adopted controller and must dispose it');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
      'progress ticks do NOT fan out into AppState.notifyListeners '
      '(status transitions still do)', () async {
    await pair();
    var notifies = 0;
    a.state.addListener(() => notifies++);

    final tmp = await Directory.systemTemp.createTemp('lanlink_bidi_perf');
    addTearDown(() => tmp.delete(recursive: true));
    final f = await writeDeterministicFile('${tmp.path}/perf.bin', 256 * 1024);
    final session = await a.state.sendFiles(
      peer: a.state.linkedPeers.single,
      files: [fileInfoFor(f, fileName: 'perf.bin', size: 256 * 1024)],
    );
    await waitFor(() => session.isTerminal);
    expect(session.status, TransferStatus.completed);
    expect(notifies, greaterThan(0),
        reason: 'membership/status changes must still notify');

    // Regression probe for the 10 Hz tick fan-out: byte updates notify the
    // session's own listeners but must NOT re-broadcast through AppState.
    final baseline = notifies;
    var sessionNotifies = 0;
    session.addListener(() => sessionNotifies++);
    final fileId = session.files.keys.first;
    session.updateBytes(fileId, 1);
    session.updateBytes(fileId, session.files[fileId]!.file.size);
    expect(sessionNotifies, greaterThan(0),
        reason: 'the session itself must keep ticking for its card');
    expect(notifies, baseline,
        reason: 'progress ticks must not trigger AppState.notifyListeners');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
