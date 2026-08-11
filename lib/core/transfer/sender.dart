import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../models/file_info.dart';
import '../platform/content_streams.dart';
import '../models/session.dart';
import '../protocol/constants.dart';
import '../security/cert_pinning.dart';
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
    CertificatePinner? pinner,
    Stream<List<int>> Function(String uri, int startAt)? contentOpener,
    this.maxParallelUploads = 3,
  })  : pinner = pinner ?? CertificatePinner(),
        _contentOpener = contentOpener ??
            ((uri, startAt) => ContentStreams.openRead(uri, start: startAt)) {
    _dio = dio ?? _defaultDio(this.pinner);
  }

  /// Upper bound on simultaneous per-file uploads within one session.
  /// Per-file HTTP round-trips dominate the wall clock for photo-roll style
  /// batches on real Wi-Fi (each file costs at least one RTT); pipelining a
  /// few uploads hides that latency without fragmenting a single big file's
  /// bandwidth. 1 restores strictly sequential v4.1.0 behavior.
  final int maxParallelUploads;

  /// Returns the current local-device info to embed in `prepare-upload`.
  final Device Function() localDeviceProvider;

  late final Dio _dio;

  /// Opens a byte stream for a `content://` source ([FileInfo.contentUri]).
  /// Defaults to the SAF platform channel; injectable so tests can feed
  /// synthetic streams without a platform.
  final Stream<List<int>> Function(String uri, int startAt) _contentOpener;

  /// Verifies peer TLS certificates against pinned fingerprints (and records
  /// cert hashes on first contact — TOFU). Shared with the default Dio's
  /// HTTP client; injectable so tests can inspect/steer it.
  final CertificatePinner pinner;

  /// Dio cancel tokens for in-flight sends, keyed by session identity so
  /// [cancelSend] can abort the HTTP work promptly.
  final Map<TransferSession, CancelToken> _inflight = {};

  static Dio _defaultDio(CertificatePinner pinner) {
    final d = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 30),
      sendTimeout: const Duration(minutes: 30),
      responseType: ResponseType.json,
    ));
    d.httpClientAdapter = _pinnedAdapter(pinner);
    return d;
  }

  /// HTTPS adapter that trusts peers by certificate fingerprint, not by CA:
  /// peers present self-signed certificates, so every connection lands in
  /// `badCertificateCallback`, where [CertificatePinner.check] enforces the
  /// pin (or records the hash on first contact).
  static HttpClientAdapter _pinnedAdapter(CertificatePinner pinner) =>
      IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback = pinner.check;
          return client;
        },
      );

  /// Declares the fingerprint we expect [peer] to present in the TLS
  /// handshake. Call before any request to the peer.
  void _pin(Device peer) => pinner.expect(peer.ip, peer.port, peer.fingerprint);

  /// Overrides [d]'s self-reported fingerprint with the cert hash actually
  /// verified (or recorded) during the TLS handshake, when available. The
  /// wire JSON is peer-controlled; the handshake is not.
  Device _withVerifiedFingerprint(Device d) {
    final observed = pinner.observed(d.ip, d.port);
    if (observed == null || observed.isEmpty) return d;
    return d.copyWith(fingerprint: observed);
  }

  /// Try a quick `/info` round-trip to confirm the peer is reachable. Returns
  /// the up-to-date [Device] info if successful, or null on failure.
  ///
  /// [cancelToken] lets the caller genuinely abort the probe: a bare
  /// `.timeout()` on the returned future only abandons it, leaving the
  /// underlying socket alive for the full 10 s connect timeout — hundreds
  /// of lingering sockets during a subnet sweep. [timeout] optionally
  /// tightens the receive budget to match the caller's per-host deadline.
  Future<Device?> probe(
    Device peer, {
    CancelToken? cancelToken,
    Duration? timeout,
  }) async {
    _pin(peer);
    try {
      final resp = await _dio.getUri<Map<String, dynamic>>(
        peer.baseUri.replace(path: LanLinkProtocol.routeInfo),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: timeout ?? const Duration(seconds: 4),
        ),
      );
      if (resp.statusCode == 200 && resp.data != null) {
        return _withVerifiedFingerprint(
            Device.fromJson(resp.data!, ip: peer.ip));
      }
    } catch (_) {}
    return null;
  }

  /// Redeems a single-use connect token (from a scanned QR) against [peer]'s
  /// LanLink connect route. Returns the peer's up-to-date [Device] info on
  /// success, or null when the token was rejected (consumed/unknown => 401)
  /// or the peer is unreachable.
  Future<Device?> connectWithToken(Device peer, String token) async {
    _pin(peer);
    try {
      final resp = await _dio.postUri<Map<String, dynamic>>(
        peer.baseUri.replace(
          path: LanLinkProtocol.routeConnect,
          queryParameters: {'token': token},
        ),
        data: localDeviceProvider().toJson(),
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      if (resp.statusCode == 200 && resp.data != null) {
        return _withVerifiedFingerprint(
            Device.fromJson(resp.data!, ip: peer.ip));
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
      files.every((f) => f.localPath != null || f.contentUri != null),
      'Sender.send requires localPath or contentUri on every file.',
    );

    _pin(peer);
    session.markStatus(TransferStatus.transferring);
    final cancelToken = CancelToken();
    _inflight[session] = cancelToken;
    try {
      await _sendInner(
        session: session,
        peer: peer,
        files: files,
        cancelToken: cancelToken,
      );
    } catch (e) {
      // Nothing inside the send pipeline may escape into an unawaited
      // future: a hostile or malformed peer response becomes a failed
      // session with a user-visible error, never an unhandled async error
      // that wedges the session at "transferring".
      if (kDebugMode) debugPrint('[sender] send failed: $e');
      if (_wasCancelled(session, e)) {
        _markPendingFiles(session, files, TransferStatus.cancelled);
        session.markStatus(TransferStatus.cancelled);
      } else {
        _failAll(
            session, files, friendlyTransferError(e, peerName: peer.alias));
      }
    } finally {
      _inflight.remove(session);
    }
  }

  Future<void> _sendInner({
    required TransferSession session,
    required Device peer,
    required List<FileInfo> files,
    required CancelToken cancelToken,
  }) async {
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
        cancelToken: cancelToken,
        // Don't throw on non-2xx — we handle 403 (decline) explicitly below.
        options: Options(
          validateStatus: (status) => status != null,
        ),
      );
    } on DioException catch (e) {
      if (_wasCancelled(session, e)) {
        _markPendingFiles(session, files, TransferStatus.cancelled);
        session.markStatus(TransferStatus.cancelled);
        return;
      }
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
    // Parse defensively: the response body is peer-controlled, so any shape
    // violation (wrong types, unknown fileIds, non-string tokens) must land
    // in the "malformed" bucket rather than throw out of this method.
    final String sessionId;
    final Map<String, String> tokens;
    final resume = <String, int>{};
    try {
      final prepData = prepResp.data as Map<String, dynamic>;
      sessionId = prepData['sessionId'] as String;
      tokens = Map<String, String>.from(prepData['files'] as Map);
      final resumeRaw = prepData['resume'];
      if (resumeRaw is Map) {
        for (final e in resumeRaw.entries) {
          resume['${e.key}'] = (e.value as num).toInt();
        }
      }
    } catch (_) {
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

    // 2. upload the accepted files.
    //
    // Files are uploaded with bounded concurrency (up to [maxParallelUploads]
    // at once). For many small files the per-file HTTP round-trip dominates
    // the wall clock; pipelining hides that latency. Tokens are per-file in
    // the LocalSend v2 protocol, so concurrent uploads to distinct files are
    // legal against LanLink and LocalSend receivers alike. A single file (or
    // a resumed file) behaves exactly as before.
    final byId = {for (final f in files) f.id: f};
    for (final fileId in tokens.keys) {
      if (byId[fileId] == null) {
        // The receiver invented a fileId we never offered — a hostile or
        // broken peer. Fail cleanly instead of throwing (C2).
        _failAll(session, files,
            'Malformed prepare-upload response (unknown file id).');
        return;
      }
    }

    final queue = tokens.entries.toList();
    var next = 0;
    var stopped = false;

    Future<void> worker() async {
      while (!stopped) {
        if (next >= queue.length) return;
        final entry = queue[next++];
        final fileId = entry.key;
        final token = entry.value;
        final info = byId[fileId]!;
        // Resolve the byte source: a filesystem path (desktop, media
        // library) or an Android content URI (SAF pick — streamed, never
        // copied).
        final Stream<List<int>> Function(int startAt) openRead;
        final int length;
        final contentUri = info.contentUri;
        if (contentUri != null) {
          openRead = (startAt) => _contentOpener(contentUri, startAt);
          // SAF reports the size at pick time; the provider owns the bytes,
          // so there is no cheap existence probe — a vanished document fails
          // the upload and lands in the normal per-file error path below.
          length = info.size;
        } else {
          final file = File(info.localPath!);
          if (!await file.exists()) {
            stopped = true;
            session.markFile(fileId, TransferStatus.failed,
                error: 'Source file missing: ${info.localPath}');
            session.markStatus(TransferStatus.failed);
            return;
          }
          openRead = file.openRead;
          length = await file.length();
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
          var startAt = resume[fileId] ?? 0;
          if (startAt < 0 || startAt >= length) startAt = 0;

          // First attempt resumes at the receiver's offset; if the receiver
          // disagrees (409 — its part changed under us) retry once from zero.
          for (var attempt = 0;; attempt++) {
            try {
              await _uploadFrom(
                session: session,
                fileId: fileId,
                openRead: openRead,
                length: length,
                startAt: startAt,
                uri: uri,
                cancelToken: cancelToken,
              );
              break;
            } on DioException catch (e) {
              final conflict = e.response?.statusCode == 409;
              if (attempt == 0 && startAt > 0 && conflict) {
                startAt = 0;
                continue;
              }
              rethrow;
            }
          }
          // Make sure the per-file byte counter is exactly the file size so
          // fraction == 1.0 cleanly (in case the source stream reported a
          // shorter count for any reason).
          session.updateBytes(fileId, length);
          session.markFile(fileId, TransferStatus.completed);
        } catch (e) {
          if (stopped) {
            // A sibling upload already decided the session's fate; this
            // failure is fallout from the shared cancel token firing.
            return;
          }
          stopped = true;
          if (kDebugMode) debugPrint('[sender] upload of $fileId failed: $e');
          // Local user hit cancel, or the receiver stopped the session
          // (its upload handler answers 403 once the session is cancelled):
          // that's a cancellation, not a failure.
          final rejectedByReceiver =
              e is DioException && e.response?.statusCode == 403;
          if (_wasCancelled(session, e) || rejectedByReceiver) {
            session.markFile(fileId, TransferStatus.cancelled);
            _markPendingFiles(session, files, TransferStatus.cancelled);
            session.markStatus(TransferStatus.cancelled);
          } else {
            session.markFile(fileId, TransferStatus.failed,
                error: friendlyTransferError(e, peerName: peer.alias));
            session.markStatus(TransferStatus.failed);
          }
          // Abort the sibling uploads still in flight.
          if (!cancelToken.isCancelled) {
            cancelToken.cancel('sibling upload ended the session');
          }
          return;
        }
      }
    }

    final workers = <Future<void>>[
      for (var i = 0; i < maxParallelUploads && i < queue.length; i++) worker(),
    ];
    await Future.wait(workers);

    if (session.status == TransferStatus.transferring) {
      session.markStatus(TransferStatus.completed);
    }
  }

  /// Cancels an in-flight send driven by [send]: aborts the HTTP transfer
  /// promptly, marks the session cancelled locally, and (best-effort) dials
  /// `POST /cancel` on [peer] so the receiving side ends its session too.
  Future<void> cancelSend({
    required TransferSession session,
    required Device peer,
  }) async {
    _pin(peer);
    _inflight[session]?.cancel('cancelled by user');
    _markPendingFiles(session, session.files.values.map((p) => p.file),
        TransferStatus.cancelled);
    session.markStatus(TransferStatus.cancelled);
    // Only sessions the receiver has acknowledged (prepare-upload returned)
    // exist on the peer; locally-minted placeholder ids are not dialable.
    final sid = session.sessionId;
    if (sid.isEmpty ||
        sid.startsWith('sending-') ||
        sid.startsWith('bluetooth-')) {
      return;
    }
    try {
      await _dio.postUri<dynamic>(
        peer.baseUri.replace(
          path: LanLinkProtocol.routeCancel,
          queryParameters: {'sessionId': sid},
        ),
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          validateStatus: (status) => status != null,
        ),
      );
    } on DioException catch (e) {
      // Best-effort: the peer may already be gone. The local session is
      // cancelled regardless.
      if (kDebugMode) debugPrint('[sender] cancel notify failed: $e');
    }
  }

  /// F3 Disconnect: tells [peer] this device is ending the pairing so it
  /// clears its side too (unlink, drop tokens, back to idle). Best-effort
  /// with tight timeouts — the local side disconnects regardless of whether
  /// the peer is still reachable. Returns true when the peer acknowledged
  /// (HTTP 200).
  Future<bool> notifyDisconnect(Device peer) async {
    _pin(peer);
    try {
      final resp = await _dio.postUri<dynamic>(
        peer.baseUri.replace(path: LanLinkProtocol.routeDisconnect),
        data: localDeviceProvider().toJson(),
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          validateStatus: (status) => status != null,
        ),
      );
      return resp.statusCode == 200;
    } on DioException catch (e) {
      // Best-effort: the peer may already be gone.
      if (kDebugMode) debugPrint('[sender] disconnect notify failed: $e');
      return false;
    }
  }

  /// True when [e] (or the session state) indicates a deliberate local
  /// cancellation rather than a failure.
  bool _wasCancelled(TransferSession session, Object e) {
    if (session.status == TransferStatus.cancelled) return true;
    return e is DioException && e.type == DioExceptionType.cancel;
  }

  /// Marks every file that hasn't reached a terminal per-file state yet.
  void _markPendingFiles(TransferSession session, Iterable<FileInfo> files,
      TransferStatus status) {
    for (final f in files) {
      final p = session.files[f.id];
      if (p == null) continue;
      if (p.status == TransferStatus.completed ||
          p.status == TransferStatus.failed ||
          p.status == TransferStatus.cancelled) {
        continue;
      }
      session.markFile(f.id, status);
    }
  }

  /// Streams the bytes from [openRead] to [uri] starting at byte [startAt],
  /// updating the session's live byte counter as chunks go out.
  Future<void> _uploadFrom({
    required TransferSession session,
    required String fileId,
    required Stream<List<int>> Function(int startAt) openRead,
    required int length,
    required int startAt,
    required Uri uri,
    CancelToken? cancelToken,
  }) async {
    session.updateBytes(fileId, startAt);
    // NOTE(perf, 2026-08-11): keep the injected `openRead` here. A custom
    // RandomAccessFile reader with bigger blocks was benchmarked at no real
    // throughput gain on loopback and it broke stream backpressure — peak
    // RSS growth on a 150MB send jumped from ~17MB to ~130MB (see
    // test/e2e_sim/large_file_e2e_test.dart's streaming guard).
    final stream = openRead(startAt);
    int sent = startAt;
    await _dio.postUri<dynamic>(
      startAt > 0
          ? uri.replace(queryParameters: {
              ...uri.queryParameters,
              'offset': '$startAt',
            })
          : uri,
      data: stream.map((chunk) {
        sent += chunk.length;
        session.updateBytes(fileId, sent);
        return chunk;
      }),
      cancelToken: cancelToken,
      options: Options(
        contentType: 'application/octet-stream',
        headers: {
          HttpHeaders.contentLengthHeader: (length - startAt).toString(),
        },
        // Don't decode the response body — we just need the status code.
        responseType: ResponseType.plain,
      ),
    );
  }

  /// Fails every file that hasn't already completed. Completed is sticky:
  /// a partial failure (e.g. file 3 of 3 errors out) must not rewrite the
  /// history of files 1–2 that already landed on the receiver.
  void _failAll(TransferSession session, List<FileInfo> files, String message) {
    for (final f in files) {
      if (session.files[f.id]?.status == TransferStatus.completed) continue;
      session.markFile(f.id, TransferStatus.failed, error: message);
    }
    session.markStatus(TransferStatus.failed);
  }

  /// Applies [status] to every file that hasn't already completed
  /// (completed is sticky — see [_failAll]).
  void _markAll(
      TransferSession session, List<FileInfo> files, TransferStatus status) {
    for (final f in files) {
      if (session.files[f.id]?.status == TransferStatus.completed) continue;
      session.markFile(f.id, status);
    }
  }
}
