// Shared helpers for the live end-to-end simulation suite (test/e2e_sim).
//
// Each test spins up two REAL peer instances — a [Receiver] hosting an HTTP
// server bound to a loopback socket, and a [Sender] dialing it over
// 127.0.0.1 — which is as close to two VMs as this sandbox allows. No mocks:
// these are the exact classes the app ships in lib/core/transfer/.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:uuid/uuid.dart';

import '../tls_test_helpers.dart';

/// Fingerprint of the shared test receiver certificate — protocol 2.1
/// fingerprints are cert hashes, so the receiver's identity must match the
/// certificate its HTTPS server presents.
String get receiverFp => testCertificate().fingerprint;

const uuid = Uuid();

Device device(String alias, String fp, int port) => Device(
      alias: alias,
      version: LanLinkProtocol.protocolVersion,
      deviceModel: 'e2e-sim',
      deviceType: LanLinkProtocol.deviceTypeHeadless,
      fingerprint: fp,
      port: port,
      protocol: 'https',
      ip: '127.0.0.1',
    );

/// Streaming sha256 of a file — never loads the whole file into memory, so
/// it is safe for the 150MB scenario.
Future<String> sha256OfFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}

/// Writes [sizeBytes] of deterministic-but-non-trivial content to [path] in
/// 1MB chunks (streamed, so generating the 150MB fixture stays cheap).
Future<File> writeDeterministicFile(String path, int sizeBytes,
    {int seed = 17}) async {
  final file = File(path);
  final sink = file.openWrite();
  const chunkSize = 1024 * 1024;
  var written = 0;
  var chunkIdx = 0;
  while (written < sizeBytes) {
    final n =
        (sizeBytes - written) < chunkSize ? (sizeBytes - written) : chunkSize;
    final chunk = Uint8List(n);
    for (var i = 0; i < n; i++) {
      chunk[i] = (i * 31 + chunkIdx * 101 + seed) % 251;
    }
    sink.add(chunk);
    written += n;
    chunkIdx++;
  }
  await sink.flush();
  await sink.close();
  return file;
}

FileInfo fileInfoFor(File f, {required String fileName, required int size}) =>
    FileInfo(
      id: uuid.v4(),
      fileName: fileName,
      size: size,
      fileType: 'other',
      localPath: f.path,
    );

TransferSession sendSessionFor(Device peer, List<FileInfo> files) =>
    TransferSession(
      sessionId: 'sending-e2e-${uuid.v4()}',
      direction: TransferDirection.send,
      peer: peer,
      files: {
        for (final f in files)
          f.id: FileProgress(file: f, status: TransferStatus.transferring),
      },
      status: TransferStatus.transferring,
    );

Future<void> waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 15)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not reached within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
