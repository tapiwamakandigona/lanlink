import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/transfer/receiver.dart';

/// End-to-end resume test against a real [Receiver] on a loopback socket:
/// an upload dies halfway, the partial bytes survive, the next
/// prepare-upload advertises the offset, and an offset upload completes
/// the file byte-for-byte.
void main() {
  late Directory tmp;
  late Directory saveDir;
  late Receiver receiver;
  late HttpClient client;
  late int port;

  Device localDevice() => Device(
        alias: 'test-receiver',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'test',
        deviceType: LanLinkProtocol.deviceTypeHeadless,
        fingerprint: 'test-fingerprint',
        port: 0,
        protocol: 'http',
        ip: '127.0.0.1',
      );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('lanlink_resume_');
    saveDir = Directory('${tmp.path}/saved');
    receiver = Receiver(
      localDeviceProvider: localDevice,
      saveDirProvider: () async => saveDir,
      onAccept: (peer, files) async =>
          AcceptDecision.accept(files.map((f) => f.id).toSet()),
      onSessionStarted: (_) {},
    );
    await receiver.start();
    port = receiver.port!;
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await receiver.stop();
    await tmp.delete(recursive: true);
  });

  Map<String, dynamic> senderInfo() => {
        'alias': 'test-sender',
        'version': LanLinkProtocol.protocolVersion,
        'deviceModel': 'test',
        'deviceType': LanLinkProtocol.deviceTypeHeadless,
        'fingerprint': 'sender-fingerprint',
        'port': 1,
        'protocol': 'http',
      };

  Future<Map<String, dynamic>> prepareUpload(FileInfo file) async {
    final req = await client.postUrl(Uri.parse(
        'http://127.0.0.1:$port${LanLinkProtocol.routePrepareUpload}'));
    req.headers.contentType = ContentType.json;
    req.write(json.encode({
      'info': senderInfo(),
      'files': {
        file.id: {
          'id': file.id,
          'fileName': file.fileName,
          'size': file.size,
          'fileType': file.fileType,
        },
      },
    }));
    final resp = await req.close();
    expect(resp.statusCode, 200);
    return json.decode(await utf8.decodeStream(resp)) as Map<String, dynamic>;
  }

  Future<int> upload({
    required String sessionId,
    required String fileId,
    required String token,
    required List<int> bytes,
    int? offset,
    int? declaredLength,
  }) async {
    final uri = Uri.parse(
      'http://127.0.0.1:$port${LanLinkProtocol.routeUpload}'
      '?sessionId=$sessionId&fileId=$fileId&token=$token'
      '${offset != null ? '&offset=$offset' : ''}',
    );
    final req = await client.postUrl(uri);
    req.headers.contentType = ContentType.binary;
    req.contentLength = declaredLength ?? bytes.length;
    req.add(bytes);
    if (declaredLength != null && declaredLength > bytes.length) {
      // Simulate a connection drop mid-upload: declare more bytes than we
      // send, then abort the request socket.
      await req.flush();
      req.abort();
      return -1;
    }
    final resp = await req.close();
    await resp.drain<void>();
    return resp.statusCode;
  }

  test('interrupted upload resumes from the receiver-advertised offset',
      () async {
    final payload = List<int>.generate(64 * 1024, (i) => (i * 31 + 7) & 0xff);
    final file = FileInfo(
      id: 'file-1',
      fileName: 'video.bin',
      size: payload.length,
      fileType: 'other',
    );

    // Attempt 1: send only the first 24 KiB, then drop the connection.
    final prep1 = await prepareUpload(file);
    expect(prep1.containsKey('resume'), isFalse,
        reason: 'nothing to resume on a first attempt');
    final token1 = (prep1['files'] as Map)[file.id] as String;
    const cut = 24 * 1024;
    await upload(
      sessionId: prep1['sessionId'] as String,
      fileId: file.id,
      token: token1,
      bytes: payload.sublist(0, cut),
      declaredLength: payload.length,
    );

    // The partial bytes must survive on disk. The abort races the server's
    // stream consumption, so poll briefly until the bytes settle.
    final partsDir = Directory('${saveDir.path}/.lanlink_parts');
    File? part;
    for (var i = 0; i < 100; i++) {
      final candidates = partsDir.existsSync()
          ? partsDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.part'))
              .toList()
          : const <File>[];
      if (candidates.length == 1 && candidates.single.lengthSync() == cut) {
        part = candidates.single;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(part, isNotNull,
        reason: 'expected a $cut-byte part file to survive the abort');
    expect(part!.lengthSync(), cut);

    // Attempt 2: receiver advertises the offset, sender continues there.
    final prep2 = await prepareUpload(file);
    final resume = prep2['resume'] as Map<String, dynamic>;
    expect(resume[file.id], cut);
    final token2 = (prep2['files'] as Map)[file.id] as String;
    final status = await upload(
      sessionId: prep2['sessionId'] as String,
      fileId: file.id,
      token: token2,
      bytes: payload.sublist(cut),
      offset: cut,
    );
    expect(status, 200);

    // The completed file matches the original payload exactly.
    final saved = saveDir
        .listSync()
        .whereType<File>()
        .singleWhere((f) => f.path.endsWith('video.bin'));
    expect(saved.readAsBytesSync(), payload);
    expect(part.existsSync(), isFalse,
        reason: 'part file is renamed away on completion');
  });

  test('stale offset is rejected with 409 so the sender restarts', () async {
    final payload = List<int>.generate(4096, (i) => i & 0xff);
    final file = FileInfo(
      id: 'file-2',
      fileName: 'doc.pdf',
      size: payload.length,
      fileType: 'other',
    );
    final prep = await prepareUpload(file);
    final token = (prep['files'] as Map)[file.id] as String;

    // Claim an offset the receiver does not have.
    final status = await upload(
      sessionId: prep['sessionId'] as String,
      fileId: file.id,
      token: token,
      bytes: payload.sublist(1024),
      offset: 1024,
    );
    expect(status, 409);
  });
}
