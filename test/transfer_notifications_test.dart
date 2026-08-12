// Exercises the Dart side of the notification bridge with a mocked platform
// channel: argument building (direction-correct text), terminal-state
// handling, and resilience to platform-side failures.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/platform/transfer_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lanlink/notifications');
  final calls = <MethodCall>[];
  Object? Function(MethodCall)? handler;

  setUp(() {
    TransferNotifications.debugForceSupported = true;
    calls.clear();
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler?.call(call);
    });
  });

  tearDown(() {
    TransferNotifications.debugForceSupported = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  TransferSession session({
    required TransferDirection direction,
    required TransferStatus status,
    String alias = 'Pixel 8',
  }) {
    final info = FileInfo(
        id: 'f1', fileName: 'photo.jpg', size: 1000, fileType: 'image');
    return TransferSession(
      sessionId: 's-1',
      direction: direction,
      peer: Device(
        alias: alias,
        version: '2.0',
        deviceModel: '',
        deviceType: 'mobile',
        fingerprint: 'fp',
        port: 53317,
        protocol: 'https',
        ip: '192.168.1.2',
      ),
      files: {'f1': FileProgress(file: info, bytes: 500, status: status)},
      status: status,
    );
  }

  test('failed SEND says "To <peer>", not "From <peer>"', () async {
    await TransferNotifications.instance.showFinal(session(
        direction: TransferDirection.send, status: TransferStatus.failed));
    expect(calls, hasLength(1));
    final args = calls.single.arguments as Map;
    expect(args['title'], 'Send failed');
    expect(args['text'], 'To Pixel 8');
    expect(args['success'], false);
  });

  test('cancelled RECEIVE still says "From <peer>"', () async {
    await TransferNotifications.instance.showFinal(session(
        direction: TransferDirection.receive,
        status: TransferStatus.cancelled));
    final args = calls.single.arguments as Map;
    expect(args['title'], 'Receive cancelled');
    expect(args['text'], 'From Pixel 8');
  });

  test('empty alias falls back to "a device"', () async {
    await TransferNotifications.instance.showFinal(session(
        direction: TransferDirection.send,
        status: TransferStatus.failed,
        alias: ''));
    final args = calls.single.arguments as Map;
    expect(args['text'], 'To a device');
  });

  test('showProgress computes bounded percent and subtitle', () async {
    await TransferNotifications.instance.showProgress(session(
        direction: TransferDirection.receive,
        status: TransferStatus.transferring));
    final args = calls.single.arguments as Map;
    expect(calls.single.method, 'showProgress');
    expect(args['progress'], 50);
    expect(args['max'], 100);
    expect(args['indeterminate'], false);
  });

  test('notification id stays stable when sender replaces pending session id',
      () async {
    final s = session(
        direction: TransferDirection.send, status: TransferStatus.transferring);
    await TransferNotifications.instance.showProgress(s);
    final firstId = (calls.single.arguments as Map)['id'];

    // Sender replaces its local pending id with the receiver-assigned id
    // after prepare-upload. The same notification row must be updated rather
    // than leaving an orphaned ongoing row in the shade.
    s.sessionId = 'receiver-assigned-id';
    s.markStatus(TransferStatus.completed);
    await TransferNotifications.instance.showFinal(s);

    expect((calls.last.arguments as Map)['id'], firstId);
  });

  test('platform-side PlatformException never escapes', () async {
    handler = (call) =>
        throw PlatformException(code: 'boom', message: 'no permission');
    // Must complete without throwing for all three entry points.
    final s = session(
        direction: TransferDirection.send, status: TransferStatus.failed);
    await TransferNotifications.instance.showFinal(s);
    await TransferNotifications.instance.showProgress(s);
    await TransferNotifications.instance.cancel(s);
    expect(calls, hasLength(3));
  });

  test('missing plugin (desktop) is silently ignored', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    final s = session(
        direction: TransferDirection.send, status: TransferStatus.completed);
    await TransferNotifications.instance.showFinal(s);
    await TransferNotifications.instance.showProgress(s);
  });

  test('showFinal on a non-terminal session posts nothing', () async {
    await TransferNotifications.instance.showFinal(session(
        direction: TransferDirection.send,
        status: TransferStatus.transferring));
    expect(calls, isEmpty);
  });
}
