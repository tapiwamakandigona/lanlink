import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../models/file_info.dart';
import '../models/session.dart';
import '../protocol/constants.dart';

/// Outcome of [Sender.send].
class SendResult {
  SendResult({required this.session, required this.success, this.error});
  final TransferSession session;
  final bool success;
  final String? error;
}

/// Drives outgoing transfers from this device to a [Device] peer.
///
/// Construction is cheap; each call to [send] starts a fresh session and
/// returns when all files have either finished, failed, or the session was
/// cancelled.
class Sender {
  Sender({
    required this.localDeviceProvider,
    Dio? dio,
  }) : _dio = dio ?? _defaultDio();

  /// Returns the current local-device info to embed in `prepare-upload`.
  final Device Function() localDeviceProvider;

  final Dio _dio;

  static Dio _defaultDio() {
    final d = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 30),
      sendTimeout: const Duration(minutes: 30),
      responseType: ResponseType.json,
    ));
    return d;
  }

  /// Try a quick `/info` round-trip to confirm the peer is reachable. Returns
  /// the up-to-date [Device] info if successful, or null on failure.
  Future<Device?> probe(Device peer) async {
    try {
      final resp = await _dio.getUri<Map<String, dynamic>>(
        peer.baseUri.replace(path: LanLinkProtocol.routeInfo),
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      if (resp.statusCode == 200 && resp.data != null) {
        return Device.fromJson(resp.data!, ip: peer.ip);
      }
    } catch (_) {}
    return null;
  }

  /// Sends [files] to [peer], creating and returning a [TransferSession].
  ///
  /// The returned session is updated live as bytes are uploaded — UI can
  /// listen to it to render progress.
  Future<TransferSession> send({
    required Device peer,
    required List<FileInfo> files,
  }) async {
    assert(
      files.every((f) => f.localPath != null),
      'Sender.send requires localPath on every file.',
    );

    final session = TransferSession(
      sessionId: 'pending',
      direction: TransferDirection.send,
      peer: peer,
      files: {
        for (final f in files)
          f.id: FileProgress(file: f, status: TransferStatus.transferring),
      },
    );

    // 1. prepare-upload
    final me = localDeviceProvider();
    final prepareUri =
        peer.baseUri.replace(path: LanLinkProtocol.routePrepareUpload);
    Response<dynamic> prepResp;
    try {
      prepResp = await _dio.postUri(
        prepareUri,
        data: {
          'info': me.toJson(),
          'files': {for (final f in files) f.id: f.toJson()},
        },
      );
    } on DioException catch (e) {
      session.markStatus(TransferStatus.failed);
      if (kDebugMode) debugPrint('[sender] prepare-upload failed: $e');
      return session;
    }

    if (prepResp.statusCode == 403) {
      session.markStatus(TransferStatus.cancelled);
      return session;
    }
    if (prepResp.statusCode != 200 || prepResp.data is! Map) {
      session.markStatus(TransferStatus.failed);
      return session;
    }
    final prepData = prepResp.data as Map<String, dynamic>;
    final sessionId = prepData['sessionId'] as String?;
    final tokens =
        (prepData['files'] as Map<String, dynamic>?)?.cast<String, String>();
    if (sessionId == null || tokens == null) {
      session.markStatus(TransferStatus.failed);
      return session;
    }

    final acceptedSession = TransferSession(
      sessionId: sessionId,
      direction: TransferDirection.send,
      peer: peer,
      files: {
        for (final f in files.where((f) => tokens.containsKey(f.id)))
          f.id: FileProgress(file: f, status: TransferStatus.transferring),
      },
    );

    // 2. upload each file in turn
    for (final entry in tokens.entries) {
      final fileId = entry.key;
      final token = entry.value;
      final info = files.firstWhere((f) => f.id == fileId);
      final file = File(info.localPath!);
      final uri = peer.baseUri.replace(
        path: LanLinkProtocol.routeUpload,
        queryParameters: {
          'sessionId': sessionId,
          'fileId': fileId,
          'token': token,
        },
      );
      try {
        final length = await file.length();
        final stream = file.openRead();
        int sent = 0;
        await _dio.postUri<dynamic>(
          uri,
          data: stream.map((chunk) {
            sent += chunk.length;
            acceptedSession.updateBytes(fileId, sent);
            return chunk;
          }),
          options: Options(
            contentType: 'application/octet-stream',
            headers: {HttpHeaders.contentLengthHeader: length.toString()},
            // Don't decode the response body — we just need the status code.
            responseType: ResponseType.plain,
          ),
        );
        acceptedSession.markFile(fileId, TransferStatus.completed);
      } catch (e) {
        if (kDebugMode) debugPrint('[sender] upload of $fileId failed: $e');
        acceptedSession.markFile(fileId, TransferStatus.failed, error: '$e');
        acceptedSession.markStatus(TransferStatus.failed);
        return acceptedSession;
      }
    }

    acceptedSession.markStatus(TransferStatus.completed);
    return acceptedSession;
  }
}
