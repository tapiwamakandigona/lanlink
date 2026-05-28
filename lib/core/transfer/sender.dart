import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../models/file_info.dart';
import '../models/session.dart';
import '../protocol/constants.dart';
import '../util/friendly_error.dart';

/// Drives outgoing transfers from this device to a [Device] peer.
///
/// Construction is cheap; each call to [send] drives a fresh session and
/// completes when all files have either finished, failed, or the session
/// was cancelled.
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

  /// Drives the LocalSend v2 send protocol on top of an existing
  /// [TransferSession]. Mutates [session] in-place as the transfer progresses
  /// so any UI bound to it sees live updates without re-pointing.
  ///
  /// The caller is responsible for inserting [session] into whatever
  /// observable collection drives the UI. This method only flips statuses,
  /// updates byte counters, and adjusts the [TransferSession.sessionId] once
  /// the receiver assigns one.
  Future<void> send({
    required TransferSession session,
    required Device peer,
    required List<FileInfo> files,
  }) async {
    assert(
      files.every((f) => f.localPath != null),
      'Sender.send requires localPath on every file.',
    );

    session.markStatus(TransferStatus.transferring);

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
        // Don't throw on non-2xx — we handle 403 (decline) explicitly below.
        options: Options(
          validateStatus: (status) => status != null,
        ),
      );
    } on DioException catch (e) {
      _failAll(session, files, friendlyTransferError(e, peerName: peer.alias));
      return;
    }

    if (prepResp.statusCode == 403) {
      _markAll(session, files, TransferStatus.cancelled);
      session.markStatus(TransferStatus.cancelled);
      return;
    }
    if (prepResp.statusCode != 200 || prepResp.data is! Map) {
      _failAll(session, files,
          friendlyHttpStatus(prepResp.statusCode, peerName: peer.alias));
      return;
    }
    final prepData = prepResp.data as Map<String, dynamic>;
    final sessionId = prepData['sessionId'] as String?;
    final tokens =
        (prepData['files'] as Map<String, dynamic>?)?.cast<String, String>();
    if (sessionId == null || tokens == null) {
      _failAll(session, files, 'Malformed prepare-upload response.');
      return;
    }

    // Track the receiver-assigned id so a future cancel can target it.
    session.sessionId = sessionId;

    // Files the receiver chose not to accept (e.g. user un-ticked them).
    for (final f in files) {
      if (!tokens.containsKey(f.id)) {
        session.markFile(f.id, TransferStatus.cancelled);
      }
    }

    // 2. upload each accepted file in turn
    for (final entry in tokens.entries) {
      final fileId = entry.key;
      final token = entry.value;
      final info = files.firstWhere((f) => f.id == fileId);
      final file = File(info.localPath!);
      if (!await file.exists()) {
        session.markFile(fileId, TransferStatus.failed,
            error: 'Source file missing: ${info.localPath}');
        session.markStatus(TransferStatus.failed);
        return;
      }
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
        // Reset to 0 in case it was set by an earlier attempt.
        session.updateBytes(fileId, 0);
        final stream = file.openRead();
        int sent = 0;
        await _dio.postUri<dynamic>(
          uri,
          data: stream.map((chunk) {
            sent += chunk.length;
            session.updateBytes(fileId, sent);
            return chunk;
          }),
          options: Options(
            contentType: 'application/octet-stream',
            headers: {HttpHeaders.contentLengthHeader: length.toString()},
            // Don't decode the response body — we just need the status code.
            responseType: ResponseType.plain,
          ),
        );
        // Make sure the per-file byte counter is exactly the file size so
        // fraction == 1.0 cleanly (in case the source stream reported a
        // shorter count for any reason).
        session.updateBytes(fileId, length);
        session.markFile(fileId, TransferStatus.completed);
      } catch (e) {
        if (kDebugMode) debugPrint('[sender] upload of $fileId failed: $e');
        session.markFile(fileId, TransferStatus.failed,
            error: friendlyTransferError(e, peerName: peer.alias));
        session.markStatus(TransferStatus.failed);
        return;
      }
    }

    session.markStatus(TransferStatus.completed);
  }

  void _failAll(TransferSession session, List<FileInfo> files, String message) {
    for (final f in files) {
      session.markFile(f.id, TransferStatus.failed, error: message);
    }
    session.markStatus(TransferStatus.failed);
  }

  void _markAll(
      TransferSession session, List<FileInfo> files, TransferStatus status) {
    for (final f in files) {
      session.markFile(f.id, status);
    }
  }
}
