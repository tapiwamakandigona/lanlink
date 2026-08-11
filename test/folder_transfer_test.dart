import 'tls_test_helpers.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/transfer/receiver.dart';
import 'package:lanlink/core/util/folder_files.dart';
import 'package:lanlink/core/util/safe_paths.dart';

void main() {
  group('splitSafeRelativePath', () {
    test('keeps clean relative paths', () {
      expect(splitSafeRelativePath('Holiday/clips/video.mp4'),
          ['Holiday', 'clips', 'video.mp4']);
      expect(splitSafeRelativePath('report.pdf'), ['report.pdf']);
    });

    test('blocks traversal and absolute tricks', () {
      expect(splitSafeRelativePath('../../etc/passwd'), ['etc', 'passwd']);
      expect(splitSafeRelativePath('/etc/passwd'), ['etc', 'passwd']);
      expect(splitSafeRelativePath(r'..\..\win.ini'), ['win.ini']);
      expect(splitSafeRelativePath('a/./b/../c.txt'), ['a', 'b', 'c.txt']);
      expect(splitSafeRelativePath('..'), ['file']);
    });

    test('sanitizes illegal filesystem characters', () {
      expect(
          splitSafeRelativePath('we?ird/na:me*.txt'), ['we_ird', 'na_me_.txt']);
    });

    test('strips control characters', () {
      expect(splitSafeRelativePath('bad\x00name\x1f.txt'), ['badname.txt']);
    });

    test('neutralizes Windows reserved device names', () {
      // A Windows receiver cannot create these — with or without extension,
      // any case. They must arrive renamed, not fail the whole transfer.
      expect(splitSafeRelativePath('CON'), ['_CON']);
      expect(splitSafeRelativePath('con.txt'), ['_con.txt']);
      expect(splitSafeRelativePath('Aux.log'), ['_Aux.log']);
      expect(splitSafeRelativePath('COM1.dump/readme.md'),
          ['_COM1.dump', 'readme.md']);
      expect(splitSafeRelativePath('nul'), ['_nul']);
      // Not reserved: COM10, CONS, console.txt.
      expect(splitSafeRelativePath('COM10.txt'), ['COM10.txt']);
      expect(splitSafeRelativePath('console.txt'), ['console.txt']);
    });

    test('strips trailing dots and spaces (invalid on Windows)', () {
      expect(splitSafeRelativePath('report.'), ['report']);
      expect(splitSafeRelativePath('notes... '), ['notes']);
      expect(splitSafeRelativePath('dir./file.txt'), ['dir', 'file.txt']);
      // Replacement of an illegal char can leave a non-dot tail; only
      // genuine trailing dots/spaces are stripped.
      expect(splitSafeRelativePath('evil.<'), ['evil._']);
    });
  });

  group('fileInfosForFolder', () {
    test('walks recursively with folder-relative wire names', () async {
      final tmp = await Directory.systemTemp.createTemp('lanlink_folder_');
      addTearDown(() => tmp.delete(recursive: true));
      final root = Directory('${tmp.path}/Holiday');
      await Directory('${root.path}/clips').create(recursive: true);
      await File('${root.path}/a.jpg').writeAsBytes([1, 2, 3]);
      await File('${root.path}/clips/v.mp4').writeAsBytes([4, 5, 6, 7]);

      final infos = await fileInfosForFolder(root.path);
      expect(infos.map((f) => f.fileName).toList(),
          ['Holiday/a.jpg', 'Holiday/clips/v.mp4']);
      expect(infos[0].size, 3);
      expect(infos[1].size, 4);
      expect(infos.every((f) => f.localPath != null), isTrue);
    });

    test('returns empty for a missing folder', () async {
      expect(await fileInfosForFolder('/nonexistent/folder'), isEmpty);
    });
  });

  group('receiver folder handling', () {
    late Directory tmp;
    late Directory saveDir;
    late Receiver receiver;
    late HttpClient client;
    late int port;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lanlink_recv_folder_');
      saveDir = Directory('${tmp.path}/saved');
      receiver = Receiver(
        certificateProvider: testCertificateProvider,
        localDeviceProvider: () => Device(
          alias: 'r',
          version: LanLinkProtocol.protocolVersion,
          deviceModel: 'test',
          deviceType: LanLinkProtocol.deviceTypeHeadless,
          fingerprint: 'r-fp',
          port: 0,
          protocol: 'https',
          ip: '127.0.0.1',
        ),
        saveDirProvider: () async => saveDir,
        onAccept: (peer, files) async =>
            AcceptDecision.accept(files.map((f) => f.id).toSet()),
        onSessionStarted: (_) {},
      );
      await receiver.start();
      port = receiver.port!;
      client = trustAllHttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await receiver.stop();
      await tmp.delete(recursive: true);
    });

    Future<void> sendFile(FileInfo file, List<int> bytes) async {
      final prepReq = await client.postUrl(Uri.parse(
          'https://127.0.0.1:$port${LanLinkProtocol.routePrepareUpload}'));
      prepReq.headers.contentType = ContentType.json;
      prepReq.write(json.encode({
        'info': {
          'alias': 's',
          'version': LanLinkProtocol.protocolVersion,
          'deviceModel': 'test',
          'deviceType': LanLinkProtocol.deviceTypeHeadless,
          'fingerprint': 's-fp',
          'port': 1,
          'protocol': 'https',
        },
        'files': {
          file.id: {
            'id': file.id,
            'fileName': file.fileName,
            'size': file.size,
            'fileType': file.fileType,
          },
        },
      }));
      final prepResp = await prepReq.close();
      expect(prepResp.statusCode, 200);
      final prep = json.decode(await utf8.decodeStream(prepResp))
          as Map<String, dynamic>;
      final token = (prep['files'] as Map)[file.id] as String;
      final upReq = await client.postUrl(Uri.parse(
          'https://127.0.0.1:$port${LanLinkProtocol.routeUpload}'
          '?sessionId=${prep['sessionId']}&fileId=${file.id}&token=$token'));
      upReq.headers.contentType = ContentType.binary;
      upReq.contentLength = bytes.length;
      upReq.add(bytes);
      final upResp = await upReq.close();
      await upResp.drain<void>();
      expect(upResp.statusCode, 200);
    }

    test('recreates folder structure under the save dir', () async {
      final bytes = List<int>.generate(2048, (i) => i & 0xff);
      await sendFile(
        FileInfo(
          id: 'f1',
          fileName: 'Holiday/clips/v.mp4',
          size: bytes.length,
          fileType: 'video',
        ),
        bytes,
      );
      final saved = File('${saveDir.path}/Holiday/clips/v.mp4');
      expect(saved.existsSync(), isTrue);
      expect(saved.readAsBytesSync(), bytes);
    });

    test('a traversal attempt cannot escape the save dir', () async {
      final bytes = [1, 2, 3, 4];
      await sendFile(
        FileInfo(
          id: 'f2',
          fileName: '../../evil.bin',
          size: bytes.length,
          fileType: 'other',
        ),
        bytes,
      );
      // The file lands inside saveDir, never above it.
      expect(File('${tmp.path}/evil.bin').existsSync(), isFalse);
      expect(File('${saveDir.path}/evil.bin').existsSync(), isTrue);
    });
  });
}
