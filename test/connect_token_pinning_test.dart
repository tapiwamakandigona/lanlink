// Behavioral tests for findings 5 + 6:
//  * one-time connect tokens: the QR payload token is single-use — the
//    first redemption succeeds, a replay is rejected with 401;
//  * fingerprint pinning: a successful connect pins the peer's fingerprint
//    (persisted) and the Device model exposes `verified`; an impostor
//    announcing a pinned alias under a different fingerprint is NOT treated
//    as the pinned device.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/discovery/connect_payload.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import 'package:lanlink/core/transfer/sender.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Device _device(String alias, String fp, int port) => Device(
      alias: alias,
      version: LanLinkProtocol.protocolVersion,
      deviceModel: 'test',
      deviceType: LanLinkProtocol.deviceTypeHeadless,
      fingerprint: fp,
      port: port,
      protocol: 'http',
      ip: '127.0.0.1',
    );

void main() {
  group('one-time connect tokens', () {
    late Receiver receiver;
    late Directory tmp;
    late int port;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lanlink_token_test_');
      receiver = Receiver(
        localDeviceProvider: () => _device('receiver', 'receiver-fp', 0),
        saveDirProvider: () async => tmp,
        onAccept: (peer, files) async => AcceptDecision.reject(),
        onSessionStarted: (_) {},
      );
      await receiver.start();
      port = receiver.port!;
    });

    tearDown(() async {
      await receiver.stop();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('token connects once, replay is rejected with 401', () async {
      final token = receiver.issueConnectToken();
      final sender =
          Sender(localDeviceProvider: () => _device('me', 'me-fp', 1));
      final stub = _device('127.0.0.1', '', port);

      final device = await sender.connectWithToken(stub, token);
      expect(device, isNotNull, reason: 'first redemption must succeed');
      expect(device!.fingerprint, 'receiver-fp');

      // Replay: consumed token must be rejected.
      final replay = await sender.connectWithToken(stub, token);
      expect(replay, isNull);

      // And the wire status for the replay is specifically 401.
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      final resp = await dio.post<String>(
        'http://127.0.0.1:$port${LanLinkProtocol.routeConnect}',
        queryParameters: {'token': token},
        data: _device('me', 'me-fp', 1).toJson(),
      );
      expect(resp.statusCode, 401);
    });

    test('minting a new token invalidates the previous one (401)', () async {
      final oldToken = receiver.issueConnectToken();
      final newToken = receiver.issueConnectToken();
      expect(receiver.isConnectTokenValid(oldToken), isFalse,
          reason: 'only the newest minted token may stay redeemable');
      expect(receiver.isConnectTokenValid(newToken), isTrue);

      final sender =
          Sender(localDeviceProvider: () => _device('me', 'me-fp', 1));
      final stub = _device('127.0.0.1', '', port);
      expect(await sender.connectWithToken(stub, oldToken), isNull,
          reason: 'a superseded token must be rejected');

      // And the wire status for the stale token is specifically 401.
      final dio = Dio(BaseOptions(validateStatus: (_) => true));
      final resp = await dio.post<String>(
        'http://127.0.0.1:$port${LanLinkProtocol.routeConnect}',
        queryParameters: {'token': oldToken},
        data: _device('me', 'me-fp', 1).toJson(),
      );
      expect(resp.statusCode, 401);

      // The newest token still works.
      expect(await sender.connectWithToken(stub, newToken), isNotNull);
    });

    test('redemption fires onConnectTokenRedeemed and consumes the token',
        () async {
      var redeemedCalls = 0;
      receiver.onConnectTokenRedeemed = () => redeemedCalls++;
      final token = receiver.issueConnectToken();
      expect(receiver.isConnectTokenValid(token), isTrue);

      final sender =
          Sender(localDeviceProvider: () => _device('me', 'me-fp', 1));
      final stub = _device('127.0.0.1', '', port);
      expect(await sender.connectWithToken(stub, token), isNotNull);

      expect(redeemedCalls, 1,
          reason: 'the UI relies on this hook to re-mint the QR');
      expect(receiver.isConnectTokenValid(token), isFalse);
    });

    test('unknown token is rejected', () async {
      final sender =
          Sender(localDeviceProvider: () => _device('me', 'me-fp', 1));
      final stub = _device('127.0.0.1', '', port);
      expect(await sender.connectWithToken(stub, 'garbage-token'), isNull);
    });

    test('ConnectPayload round-trips the token', () {
      const payload = ConnectPayload(
        ip: '192.168.1.7',
        port: 53317,
        alias: 'Anna',
        fingerprint: 'fp-a',
        token: 'tok-123',
      );
      final parsed = ConnectPayload.tryParse(payload.toQrString());
      expect(parsed, isNotNull);
      expect(parsed!.token, 'tok-123');
    });

    test('AppState.connectWithToken pins the fingerprint => verified peer',
        () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettings.load();
      final state = AppState.forScreenshots(settings: settings);
      state.debugInstallSender(
          Sender(localDeviceProvider: () => _device('me', 'me-fp', 1)));

      final token = receiver.issueConnectToken();
      final device =
          await state.connectWithToken('127.0.0.1:$port', token);
      expect(device, isNotNull);
      expect(settings.isPinned('receiver-fp'), isTrue,
          reason: 'a successful connect must pin the peer fingerprint');
      expect(state.peers['receiver-fp']!.verified, isTrue);
    });
  });

  group('fingerprint pinning / verified flag', () {
    late AppSettings settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettings.load();
    });

    test('pins persist across settings reloads', () async {
      await settings.pinFingerprint('fp-a');
      final reloaded = await AppSettings.load();
      expect(reloaded.isPinned('fp-a'), isTrue);
      expect(reloaded.isPinned('fp-b'), isFalse);
    });

    test('pinned peer shows verified; impostor with same alias does not',
        () async {
      await settings.pinFingerprint('fp-real');
      final state = AppState.forScreenshots(settings: settings);

      state.debugPeerSeen(_device('Annas Laptop', 'fp-real', 53317));
      state.debugPeerSeen(_device('Annas Laptop', 'fp-evil', 53317));

      final byFp = state.peers;
      expect(byFp['fp-real']!.verified, isTrue);
      expect(byFp['fp-evil']!.verified, isFalse,
          reason: 'a familiar alias with a different fingerprint must '
              'never inherit the pinned/verified status');
      expect(byFp['fp-evil'], isNot(same(byFp['fp-real'])));
    });

    test('verified is local-only and never serialized to the wire', () {
      final d = _device('me', 'fp', 1).copyWith(verified: true);
      expect(d.verified, isTrue);
      expect(d.toJson().containsKey('verified'), isFalse);
    });
  });
}
