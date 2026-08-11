// Behavioral tests for findings 8 + 9:
//  * terminal (cancelled/failed/completed) sessions must stay in the visible
//    session list, with their terminal status, until the user dismisses them;
//  * "+ Add files": a send started while another send session to the same
//    peer is still visible joins that session's group (state-level API;
//    Stage 2 wires the UI).

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Device _device(String alias, String fp) => Device(
      alias: alias,
      version: LanLinkProtocol.protocolVersion,
      deviceModel: 'test',
      deviceType: LanLinkProtocol.deviceTypeHeadless,
      fingerprint: fp,
      port: 53317,
      protocol: 'https',
      ip: '127.0.0.1',
    );

FileInfo _file(String id) =>
    FileInfo(id: id, fileName: '$id.bin', size: 10, fileType: 'other');

TransferSession _session(String id, Device peer, TransferStatus status) =>
    TransferSession(
      sessionId: id,
      direction: TransferDirection.send,
      peer: peer,
      files: {'f-$id': FileProgress(file: _file('f-$id'))},
      status: status,
    );

void main() {
  late AppState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AppState.forScreenshots(settings: await AppSettings.load());
  });

  group('terminal sessions stay visible until dismissed', () {
    test('cancelled and failed sessions do not vanish', () {
      final peer = _device('Anna', 'fp-a');
      final cancelled = _session('s1', peer, TransferStatus.cancelled);
      final failed = _session('s2', peer, TransferStatus.failed);
      state.seedForScreenshots(peers: [peer], sessions: [cancelled, failed]);

      expect(state.visibleSessions, containsAll([cancelled, failed]));
      expect(state.visibleSessions.map((s) => s.status),
          containsAll([TransferStatus.cancelled, TransferStatus.failed]));
    });

    test('dismissSession hides a terminal session but keeps it in sessions',
        () {
      final peer = _device('Anna', 'fp-a');
      final done = _session('s1', peer, TransferStatus.completed);
      state.seedForScreenshots(peers: [peer], sessions: [done]);

      state.dismissSession(done);
      expect(state.visibleSessions, isNot(contains(done)));
      expect(state.sessions, contains(done),
          reason: 'dismiss only hides; history keeps the session');
    });

    test('an active session cannot be dismissed', () {
      final peer = _device('Anna', 'fp-a');
      final active = _session('s1', peer, TransferStatus.transferring);
      state.seedForScreenshots(peers: [peer], sessions: [active]);

      state.dismissSession(active);
      expect(state.visibleSessions, contains(active));
    });

    test('dismissFinishedSessions clears exactly the terminal ones', () {
      final peer = _device('Anna', 'fp-a');
      final active = _session('s1', peer, TransferStatus.transferring);
      final done = _session('s2', peer, TransferStatus.completed);
      final failed = _session('s3', peer, TransferStatus.failed);
      state.seedForScreenshots(peers: [peer], sessions: [active, done, failed]);

      state.dismissFinishedSessions();
      expect(state.visibleSessions, [active]);
    });
  });

  group('session grouping for "+ Add files"', () {
    test('a second send to the same peer joins one group', () async {
      final peer = _device('Anna', 'fp-a');
      await state.sendFiles(peer: peer, files: [_file('a')]);
      await state.sendFiles(peer: peer, files: [_file('b')]);

      final sends = state.sessions
          .where((s) => s.direction == TransferDirection.send)
          .toList();
      expect(sends, hasLength(2));
      final groupId = sends.first.groupId;
      expect(groupId, isNotNull);
      expect(sends.map((s) => s.groupId), everyElement(groupId),
          reason: 'both sends to the same peer must share one group');
      expect(state.sessionsInGroup(groupId!), hasLength(2));
    });

    test('sends to a different peer do not join the group', () async {
      final anna = _device('Anna', 'fp-a');
      final bob = _device('Bob', 'fp-b');
      await state.sendFiles(peer: anna, files: [_file('a')]);
      await state.sendFiles(peer: bob, files: [_file('b')]);

      final sends = state.sessions.toList();
      final bobSession = sends.firstWhere((s) => s.peer.fingerprint == 'fp-b');
      expect(bobSession.groupId, isNull,
          reason: 'a lone send to another peer stands alone');
    });

    test('a dismissed session does not attract new sends into its group',
        () async {
      final peer = _device('Anna', 'fp-a');
      await state.sendFiles(peer: peer, files: [_file('a')]);
      final first = state.sessions.first;
      first.markStatus(TransferStatus.completed);
      state.dismissSession(first);

      await state.sendFiles(peer: peer, files: [_file('b')]);
      final second = state.sessions.first;
      expect(second.groupId, isNull);
    });
  });
}
