import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../models/device.dart';
import '../models/file_info.dart';
import '../models/session.dart';
import '../protocol/constants.dart';
import '../security/device_certificate.dart';
import '../util/safe_paths.dart';

/// Outcome the UI returns when asked to approve an incoming transfer.
class AcceptDecision {
  AcceptDecision.accept(this.fileIdsToAccept) : reject = false;
  AcceptDecision.reject()
      : fileIdsToAccept = const {},
        reject = true;

  final Set<String> fileIdsToAccept;
  final bool reject;
}

/// Signature for "should we accept this incoming transfer?" callback.
typedef AcceptHandler = Future<AcceptDecision> Function(
  Device peer,
  List<FileInfo> files,
);

/// Signature called when a new active receive session is created.
typedef SessionStartedHandler = void Function(TransferSession session);

/// Hosts the HTTP server and turns LocalSend-protocol requests into
/// [TransferSession]s. The class itself does not own UI state — instead,
/// it calls back to the `onAccept` and `onSessionStarted` handlers it's
/// constructed with.
class Receiver {
  Receiver({
    required this.localDeviceProvider,
    required this.saveDirProvider,
    required this.onAccept,
    required this.onSessionStarted,
    this.onPeerSeen,
    this.idleTimeout = const Duration(minutes: 5),
    this.certificateProvider = DeviceCertificate.load,
    this.connectTokenReplayGrace = const Duration(seconds: 45),
  });

  /// Supplies the TLS identity the server presents. Defaults to the
  /// persisted per-install certificate ([DeviceCertificate.load]);
  /// injectable so tests can share one pre-generated certificate.
  final Future<DeviceCertificate> Function() certificateProvider;

  /// The certificate the running server presents (set by [start]).
  DeviceCertificate? get certificate => _certificate;
  DeviceCertificate? _certificate;

  /// How long a receive session may sit with no sender activity (no bytes,
  /// no upload calls) before the idle reaper fails it. Without this, a
  /// sender that dies right after prepare-upload leaves the session pending
  /// forever — pinning the Android foreground service and the scan
  /// throttle. Injectable so tests can shrink it.
  final Duration idleTimeout;

  /// Returns the current local-device info (alias, port, fingerprint, etc.).
  /// We accept it as a provider so settings changes take effect without
  /// restarting the server.
  final Device Function() localDeviceProvider;

  /// Returns the directory to save incoming files into.
  final Future<Directory> Function() saveDirProvider;

  final AcceptHandler onAccept;
  final SessionStartedHandler onSessionStarted;

  /// Called when a peer reveals itself through a `/register` call so the
  /// receiving side can learn (or refresh) the sender's alias and details.
  final void Function(Device peer)? onPeerSeen;

  /// Called when a peer successfully redeems a connect token via
  /// [LanLinkProtocol.routeConnect] *and* identifies itself with a usable
  /// fingerprint. This is the receiver-side half of symmetric pairing
  /// (F3): the callback pins/links the caller so trust applies both ways.
  void Function(Device peer)? onPeerConnected;

  /// Called when a linked peer dials [LanLinkProtocol.routeDisconnect].
  /// Must return true when the disconnect was accepted (the peer was
  /// actually linked and its identity checks out) — the route answers 403
  /// otherwise so strangers can't tear sessions down.
  bool Function(Device peer)? onPeerDisconnected;

  /// Trust gate for pushes: when this returns true for a fingerprint the
  /// peer has been disconnected and must re-pair, so `/prepare-upload` is
  /// rejected with 403 before the user is ever prompted.
  bool Function(String fingerprint)? isPeerBlocked;

  HttpServer? _httpServer;
  final _uuid = const Uuid();
  static const _platform = MethodChannel('lanlink/received_files');

  /// Active receive sessions, keyed by sessionId.
  final Map<String, _PendingSession> _pending = {};

  /// Part-file paths with a write currently in flight, so two sessions can
  /// never interleave bytes into the same part file (the second writer is
  /// answered 409 instead).
  final Set<String> _activePartPaths = {};

  /// Serializes the pick-unique-name + rename step at the end of an upload
  /// (see the finalize comment in [_handleUpload]).
  Future<void> _finalizeQueue = Future.value();

  Future<T> _withFinalizeLock<T>(Future<T> Function() action) {
    final prev = _finalizeQueue;
    final done = Completer<void>();
    _finalizeQueue = done.future;
    return prev.then((_) => action()).whenComplete(done.complete);
  }

  bool get isRunning => _httpServer != null;
  int? get port => _httpServer?.port;

  Future<void> start() async {
    if (_httpServer != null) return;

    final router = Router()
      ..get(LanLinkProtocol.routeInfo, _handleInfo)
      ..head(LanLinkProtocol.routeInfo, _handleInfo)
      ..post(LanLinkProtocol.routeRegister, _handleRegister)
      ..post(LanLinkProtocol.routePrepareUpload, _handlePrepareUpload)
      ..post(LanLinkProtocol.routeUpload, _handleUpload)
      ..post(LanLinkProtocol.routeCancel, _handleCancel)
      ..post(LanLinkProtocol.routeConnect, _handleConnect)
      ..get(LanLinkProtocol.routeConnect, _handleConnect)
      ..post(LanLinkProtocol.routeDisconnect, _handleDisconnect);

    final handler =
        const Pipeline().addMiddleware(_logging()).addHandler(router.call);

    final desired = localDeviceProvider().port;
    // HTTPS-only (protocol 2.1): the presented certificate IS the device
    // identity — its SHA-256 hash is the fingerprint peers pin.
    _certificate = await certificateProvider();
    _httpServer = await _bindWithFallback(handler, desired);

    // Conservative idle reaper (S6): sweep once a minute for sessions whose
    // sender went silent. The check interval is coarse on purpose — the
    // reaper is a safety net, not a liveness monitor.
    _idleReaper?.cancel();
    _idleReaper = Timer.periodic(
      const Duration(minutes: 1),
      (_) => reapIdleSessions(),
    );
  }

  /// Age limit after which an orphaned .part file stops being useful as a
  /// resume head start and only wastes disk.
  static const partFileTtl = Duration(days: 7);

  /// Whether stale-part pruning already ran for this receiver instance.
  bool _partsPruned = false;

  /// Deletes stale partial files left by transfers that never completed.
  /// Fresh parts stay: they are the resume head start for a retry. Runs
  /// lazily (once per instance) off the first part-file access, so it adds
  /// no startup I/O and no extra saveDirProvider calls; failures are
  /// irrelevant.
  @visibleForTesting
  Future<void> prunePartFiles(Directory saveDir) async {
    try {
      final partsDir = Directory(p.join(saveDir.path, '.lanlink_parts'));
      if (!await partsDir.exists()) return;
      final cutoff = DateTime.now().subtract(partFileTtl);
      await for (final entity in partsDir.list()) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Timer? _idleReaper;

  /// Fails (and forgets) every pending session with no sender activity —
  /// no upload call, no bytes — for at least [idleTimeout]. Public and
  /// clock-injectable so tests can drive it without waiting wall time.
  void reapIdleSessions({DateTime? now}) {
    final t = now ?? DateTime.now();
    final stale = _pending.entries
        .where((e) => t.difference(e.value.lastActivity) >= idleTimeout)
        .map((e) => e.key)
        .toList();
    for (final id in stale) {
      final ps = _pending.remove(id);
      if (ps == null) continue;
      for (final f in ps.session.files.values) {
        if (f.status != TransferStatus.transferring &&
            f.status != TransferStatus.awaitingAccept) {
          continue;
        }
        ps.session.markFile(f.file.id, TransferStatus.failed,
            error: 'No activity from sender — transfer timed out.');
      }
      ps.session.markStatus(TransferStatus.failed);
    }
  }

  /// Binds the HTTPS server on [desired], falling back to nearby ports and
  /// finally an OS-assigned ephemeral port. Another LanLink (or LocalSend)
  /// instance on the same machine must not take the whole app down.
  Future<HttpServer> _bindWithFallback(Handler handler, int desired) async {
    final candidates = <int>[
      desired,
      for (var i = 1; i <= 9; i++) desired + i,
      0,
    ];
    Object? lastError;
    for (final port in candidates) {
      try {
        final server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          port,
          securityContext: _certificate!.securityContext(),
        );
        if (port != desired) {
          debugPrint('[server] port $desired unavailable, '
              'listening on ${server.port} instead');
        }
        return server;
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? const SocketException('could not bind any port');
  }

  Future<void> stop() async {
    _idleReaper?.cancel();
    _idleReaper = null;
    final s = _httpServer;
    _httpServer = null;
    if (s != null) await s.close(force: true);
  }

  Middleware _logging() => (Handler inner) => (Request req) async {
        final start = DateTime.now();
        final resp = await inner(req);
        if (kDebugMode) {
          final ms = DateTime.now().difference(start).inMilliseconds;
          debugPrint('[server] ${req.method} ${req.requestedUri.path} '
              '-> ${resp.statusCode} (${ms}ms)');
        }
        return resp;
      };

  // ---- Handlers ----

  Response _handleInfo(Request req) {
    final me = localDeviceProvider();
    return Response.ok(
      json.encode(me.toJson()),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _handleRegister(Request req) async {
    // The register body carries the sender's own device info. Use it so the
    // receiving side learns (and refreshes) the sender's alias instead of
    // showing a stale cached name.
    // Read outside the try: an oversized body aborts via a shelf
    // HijackException that must propagate, not be swallowed below.
    final body = await _readBoundedControlBody(req, _maxDeviceInfoBodyBytes);
    try {
      if (body.isNotEmpty) {
        final decoded = json.decode(body);
        if (decoded is Map<String, dynamic>) {
          final connInfo =
              req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
          final ip = connInfo?.remoteAddress.address;
          if (ip != null && ip.isNotEmpty) {
            onPeerSeen?.call(Device.fromJson(decoded, ip: ip));
          }
        }
      }
    } catch (_) {
      // Malformed register payloads are not fatal; just ignore them.
    }
    final me = localDeviceProvider();
    return Response.ok(
      json.encode(me.toJson()),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _handlePrepareUpload(Request req) async {
    final raw = await _readBoundedControlBody(req, _maxPrepareUploadBodyBytes);
    Map<String, dynamic> body;
    try {
      body = json.decode(raw) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: 'invalid json: $e');
    }
    final info = body['info'];
    final filesRaw = body['files'];
    if (info is! Map<String, dynamic> || filesRaw is! Map<String, dynamic>) {
      return Response.badRequest(body: 'missing info or files');
    }

    final peerIp =
        (req.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address ??
            '0.0.0.0';
    final peer = Device.fromJson(info, ip: peerIp);

    // F3 server-side enforcement: a disconnected peer cannot push files.
    // Rejected before the consent prompt, so the local user is never
    // bothered by a peer that must re-pair first.
    if (isPeerBlocked?.call(peer.fingerprint) ?? false) {
      return Response.forbidden('disconnected - pair again to send');
    }

    // Parse each file entry totally: one malformed entry from a hostile or
    // buggy peer yields a clean 400, never a thrown TypeError turned into a
    // 500. An empty/all-invalid file set is itself a bad request.
    final files = <FileInfo>[];
    for (final e in filesRaw.values) {
      final fi = FileInfo.tryFromJson(e);
      if (fi == null) {
        return Response.badRequest(body: 'invalid file entry');
      }
      files.add(fi);
    }
    if (files.isEmpty) {
      return Response.badRequest(body: 'no valid files');
    }

    final decision = await onAccept(peer, files);
    if (decision.reject || decision.fileIdsToAccept.isEmpty) {
      return Response.forbidden('declined');
    }

    final accepted =
        files.where((f) => decision.fileIdsToAccept.contains(f.id)).toList();
    if (accepted.isEmpty) {
      return Response.forbidden('declined');
    }

    final sessionId = _uuid.v4();
    final tokens = <String, String>{
      for (final f in accepted) f.id: _uuid.v4(),
    };

    final session = TransferSession(
      sessionId: sessionId,
      direction: TransferDirection.receive,
      peer: peer,
      files: {
        for (final f in accepted)
          f.id: FileProgress(file: f, status: TransferStatus.transferring),
      },
    );

    _pending[sessionId] = _PendingSession(
      session: session,
      tokens: tokens,
      files: {for (final f in accepted) f.id: f},
    );
    onSessionStarted(session);

    // LanLink extension: report how much of each file we already hold from
    // an interrupted earlier attempt so the sender can resume mid-file.
    // LocalSend clients simply ignore the extra key.
    final resume = <String, int>{};
    try {
      final saveDir = await saveDirProvider();
      for (final f in accepted) {
        final part = await _partFileFor(saveDir, peer, f);
        if (!await part.exists()) continue;
        final len = await part.length();
        if (len > 0 && len < f.size) {
          resume[f.id] = len;
        } else if (len >= f.size) {
          // A part at least as big as the announced file can't be trusted
          // (size changed or the rename was interrupted) — start over.
          try {
            await part.delete();
          } catch (_) {}
        }
      }
    } catch (_) {
      // Resume is best-effort; never block the transfer over it.
    }

    return Response.ok(
      json.encode({
        'sessionId': sessionId,
        'files': tokens,
        if (resume.isNotEmpty) 'resume': resume,
      }),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _handleUpload(Request req) async {
    final sessionId = req.url.queryParameters['sessionId'];
    final fileId = req.url.queryParameters['fileId'];
    final token = req.url.queryParameters['token'];
    if (sessionId == null || fileId == null || token == null) {
      return Response.badRequest(body: 'missing sessionId/fileId/token');
    }
    final ps = _pending[sessionId];
    if (ps == null) return Response.notFound('no such session');
    if (ps.tokens[fileId] != token) return Response.forbidden('bad token');
    final info = ps.files[fileId];
    if (info == null) return Response.notFound('no such file');
    // Any authenticated upload call counts as sender activity.
    ps.touch();
    // Writes are only accepted while the session is actively transferring.
    // A cancelled/failed session must never accept more bytes.
    if (ps.session.status != TransferStatus.transferring) {
      return _drainAndReject(req.read());
    }

    final Directory saveDir;
    try {
      saveDir = await saveDirProvider();
      await saveDir.create(recursive: true);
    } catch (e) {
      _failSession(sessionId, ps, fileId, 'Cannot create save folder: $e');
      return Response.internalServerError(body: 'cannot create save folder');
    }

    // Resume support: the sender may continue an interrupted upload at the
    // byte offset we advertised in prepare-upload. The offset must match
    // the part file exactly — otherwise the sender restarts from zero.
    final offset = int.tryParse(req.url.queryParameters['offset'] ?? '0') ?? 0;
    // A negative or past-the-end offset is never something a well-behaved
    // sender asks for (resume offsets are the receiver's own advertised
    // part length, 0 < offset < size). Reject rather than let it drive the
    // write into append/truncate corner cases.
    if (offset < 0 || offset > info.size) {
      return Response.badRequest(body: 'invalid offset $offset');
    }
    final partFile = await _partFileFor(saveDir, ps.session.peer, info);
    if (offset > 0) {
      final have = await partFile.exists() ? await partFile.length() : 0;
      if (have != offset) {
        return Response(
          409,
          body: 'offset mismatch: receiver has $have bytes',
        );
      }
    }

    // Upload tokens are single-use. Consume the token only once we're about
    // to write (a 409 offset mismatch above must not burn it — the sender
    // legitimately retries from zero with the same token). A replay of a
    // consumed token is a hostile or duplicated request: reject with 401 so
    // two concurrent uploads can never interleave writes into one part file.
    if (!ps.consumedTokens.add(token)) {
      return Response(401, body: 'upload token already used');
    }

    // The single-use token above only protects within one session. Two
    // *different* live sessions can still target the same part file (same
    // peer re-offering the same file concurrently), so claim the part path
    // exclusively for the duration of the write. Every exit below must
    // release the claim.
    if (!_activePartPaths.add(partFile.path)) {
      return Response(409, body: 'file is already being received');
    }

    IOSink? sink;
    try {
      sink = partFile.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
    } catch (e) {
      _activePartPaths.remove(partFile.path);
      _failSession(sessionId, ps, fileId, 'Cannot open ${partFile.path}: $e');
      // Terse for the same reason as the write-failure below: exception
      // text carries local paths.
      return Response.internalServerError(body: 'cannot open temp file');
    }

    int received = offset;
    int unflushed = 0;
    String finalPath;
    var aborted = false;
    var oversized = false;
    var drainedAfterAbort = 0;
    try {
      await for (final chunk in req.read()) {
        // Stop writing the moment the session leaves the active state
        // (e.g. the local user hit Stop and /cancel raced this upload).
        // Keep draining (and discarding) the rest of the body on the same
        // subscription so the sender reliably receives our 403 instead of
        // a broken pipe — but only up to the same bound as
        // [_drainAndReject]: past that, stop reading entirely so a peer
        // cannot keep this handler pinned by streaming forever.
        if (!aborted && ps.session.status != TransferStatus.transferring) {
          aborted = true;
          try {
            await sink.close();
          } catch (_) {}
        }
        // Never write past the size the user consented to: a hostile or
        // buggy sender that streams extra bytes gets its file failed and
        // the rest of the body discarded under the same drain bound.
        if (!aborted && received + chunk.length > info.size) {
          aborted = true;
          oversized = true;
          try {
            await sink.close();
          } catch (_) {}
        }
        if (aborted) {
          drainedAfterAbort += chunk.length;
          if (drainedAfterAbort > _maxDrainBytes) break;
          continue;
        }
        sink.add(chunk);
        received += chunk.length;
        unflushed += chunk.length;
        ps.touch();
        // Backpressure: without periodic flushes every added chunk queues
        // in memory until EOF, so on a fast network the heap grows toward
        // the file size. Awaiting the flush pauses the request stream
        // (`await for` propagates the pause), bounding buffered bytes.
        if (unflushed >= _flushEveryBytes) {
          unflushed = 0;
          await sink.flush();
        }
        ps.session.updateBytes(fileId, received);
      }
      if (oversized) {
        // The part file now holds bytes we can't trust (the announced size
        // was a lie); drop it so a later resume can't build on it.
        try {
          await partFile.delete();
        } catch (_) {}
        _activePartPaths.remove(partFile.path);
        _failSession(
            sessionId,
            ps,
            fileId,
            'Sender streamed more bytes than the consented size '
            '(${info.size}).');
        return Response.badRequest(
            body: 'body exceeds declared file size ${info.size}');
      }
      if (aborted || ps.session.status != TransferStatus.transferring) {
        throw const _SessionNoLongerActive();
      }
      await sink.flush();
      await sink.close();
      // Lower-bound check: the sender declared info.size bytes but the body
      // ended early (a short Content-Length, a truncated source, a dropped
      // stream that still closed cleanly). Finalizing here would publish a
      // silently truncated file as "completed". Keep the partial bytes as a
      // resume head start and fail the file instead. (The upper bound —
      // more bytes than declared — is handled by the `oversized` path
      // above.) Skipped only when the peer declared size 0, which
      // legitimately streams no body.
      if (info.size > 0 && received < info.size) {
        _activePartPaths.remove(partFile.path);
        _failSession(
          sessionId,
          ps,
          fileId,
          'Transfer ended early: got $received of ${info.size} bytes.',
        );
        return Response.badRequest(
            body: 'incomplete body: $received of ${info.size} bytes');
      }
      // Folder transfers carry a relative path in fileName; recreate the
      // structure under the save dir (sanitized, traversal-proof).
      final segments = splitSafeRelativePath(info.fileName);
      var targetDir = saveDir;
      if (segments.length > 1) {
        targetDir = Directory(
          p.joinAll(
              [saveDir.path, ...segments.sublist(0, segments.length - 1)]),
        );
        await targetDir.create(recursive: true);
      }
      // Finalize under a lock: the exists-check and the rename are not
      // atomic, so two sessions completing the same file name concurrently
      // could both pick the same path and the second rename would silently
      // overwrite the first file. [uniqueOutputPath] additionally reserves
      // the name in-memory, which covers pipelined uploads inside one
      // session (two same-named files in flight at once).
      final destDir = targetDir;
      finalPath = await _withFinalizeLock(() async {
        final path = await uniqueOutputPath(destDir, segments.last);
        try {
          await partFile.rename(path);
        } finally {
          _releaseReservedPath(path);
        }
        return path;
      });
      _activePartPaths.remove(partFile.path);
    } on _SessionNoLongerActive {
      // Session was cancelled (or failed) while this upload streamed in.
      // Keep whatever made it to disk as a resume head start, but do not
      // touch the (terminal, sticky) session status.
      try {
        await sink.close();
      } catch (_) {}
      _activePartPaths.remove(partFile.path);
      return Response.forbidden('session cancelled');
    } catch (e) {
      // Keep the part file: whatever made it to disk is the head start for
      // the next attempt.
      try {
        await sink.close();
      } catch (_) {}
      _activePartPaths.remove(partFile.path);
      _failSession(sessionId, ps, fileId, '$e');
      // Deliberately terse: the exception text contains local filesystem
      // paths, which are none of the peer's business. The local user gets
      // the detailed reason through _failSession above.
      return Response.internalServerError(body: 'write failed');
    }

    // On Android, the path we just wrote to is almost always inside the app's
    // private external files directory (because scoped storage blocks direct
    // writes to /storage/emulated/0/Download from API 30+). Publish a copy to
    // MediaStore.Downloads so the file is visible to the user in the Files /
    // Downloads app exactly like ShareIt / LocalSend.
    final pubSegments = splitSafeRelativePath(info.fileName);
    final publicLocation = await _publishToPublicDownloads(
      sourcePath: finalPath,
      fileName: pubSegments.last,
      subDir: pubSegments.length > 1
          ? pubSegments.sublist(0, pubSegments.length - 1).join('/')
          : null,
    );
    final visiblePath = publicLocation ?? finalPath;
    if (ps.session.status != TransferStatus.transferring) {
      // Cancelled while we were publishing; the file stays on disk but the
      // session outcome must remain terminal.
      return Response.forbidden('session cancelled');
    }
    ps.session
        .markFile(fileId, TransferStatus.completed, savedPath: visiblePath);

    // If every file in the session is done, mark the session complete.
    final allDone = ps.session.files.values
        .every((f) => f.status == TransferStatus.completed);
    if (allDone) {
      ps.session.markStatus(TransferStatus.completed);
      _pending.remove(sessionId);
    }
    return Response.ok('ok');
  }

  /// Politely rejects an upload whose session is no longer active: drains
  /// (and discards) a bounded amount of the request body first so the
  /// sending side reliably receives the 403 instead of a broken pipe, then
  /// answers 403 so the sender maps it to "cancelled".
  Future<Response> _drainAndReject(Stream<List<int>> body) async {
    var drained = 0;
    try {
      await for (final chunk in body) {
        drained += chunk.length;
        if (drained > _maxDrainBytes) break;
      }
    } catch (_) {}
    return Response.forbidden('session cancelled');
  }

  /// The most a rejected/aborted upload body is ever drained before we
  /// stop reading, both pre-stream ([_drainAndReject]) and mid-stream.
  static const _maxDrainBytes = 32 * 1024 * 1024;

  /// How many written bytes accumulate before the upload loop awaits a
  /// [IOSink.flush] — the disk-backpressure interval. Large enough that
  /// the flush overhead is negligible, small enough to bound the heap.
  static const _flushEveryBytes = 8 * 1024 * 1024;

  /// Cap for `/prepare-upload` bodies. The largest legitimate control
  /// payload: a huge folder transfer sends one [FileInfo] JSON entry per
  /// file (~200–300 bytes each, plus optional base64 image previews), so
  /// even a 10k-file folder is ~3MB. 8MB leaves >2x headroom while staying
  /// far below the memory a flooding peer could otherwise pin.
  static const _maxPrepareUploadBodyBytes = 8 * 1024 * 1024;

  /// Cap for `/register` and `/connect` bodies, which carry a single
  /// device-info JSON object (well under 1KB in practice).
  static const _maxDeviceInfoBodyBytes = 64 * 1024;

  /// Reads a control-route request body into a string without ever
  /// buffering more than [maxBytes]: as soon as the declared
  /// Content-Length or the streamed bytes exceed the cap, the connection
  /// is answered 413 and torn down via [_rejectTooLargeAndAbort], so an
  /// oversized flood is neither buffered nor drained to the end.
  Future<String> _readBoundedControlBody(Request req, int maxBytes) async {
    final declared = req.contentLength;
    if (declared != null && declared > maxBytes) {
      _rejectTooLargeAndAbort(req);
    }
    final buf = BytesBuilder(copy: false);
    await for (final chunk in req.read()) {
      buf.add(chunk);
      if (buf.length > maxBytes) _rejectTooLargeAndAbort(req);
    }
    return utf8.decode(buf.takeBytes(), allowMalformed: true);
  }

  /// Hijacks the connection to answer 413 (payload too large) and closes
  /// the socket immediately. A plain [Response] is not enough here:
  /// `dart:io` drains any unread request body before completing a
  /// keep-alive response, which would let a flooding peer make the server
  /// read the whole oversized payload anyway. Throws shelf's
  /// HijackException, so this never returns.
  Never _rejectTooLargeAndAbort(Request req) {
    req.hijack((channel) {
      channel.sink.add(ascii.encode('HTTP/1.1 413 Payload Too Large\r\n'
          'connection: close\r\n'
          'content-length: 0\r\n'
          '\r\n'));
      channel.sink.close();
    });
  }

  /// Marks [fileId] and the whole session failed and drops the session from
  /// [_pending] so its upload tokens are dead and the map cannot grow
  /// unboundedly with terminal sessions.
  void _failSession(
      String sessionId, _PendingSession ps, String fileId, String error) {
    ps.session.markFile(fileId, TransferStatus.failed, error: error);
    ps.session.markStatus(TransferStatus.failed);
    _pending.remove(sessionId);
  }

  /// Locally cancels an active receive session (e.g. the user hit Stop).
  /// In-flight uploads for it are rejected mid-stream, so the sending side
  /// observes a 403 and marks its own session cancelled.
  void cancelSession(String sessionId) {
    final ps = _pending.remove(sessionId);
    if (ps != null) ps.session.markStatus(TransferStatus.cancelled);
  }

  /// On Android publishes [sourcePath] into the user-visible
  /// `Downloads/LanLink/` MediaStore collection and returns a human-readable
  /// path like `Downloads/LanLink/foo.bin`. The source file is removed if the
  /// publish succeeds so we don't end up with two copies on disk.
  ///
  /// On Windows / Linux / macOS this just runs the (optional) media scanner
  /// hook and returns null — the file is already saved at [sourcePath] in a
  /// user-visible location.
  Future<String?> _publishToPublicDownloads({
    required String sourcePath,
    required String fileName,
    String? subDir,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final publicPath = await _platform.invokeMethod<String>(
        'publishToDownloads',
        {
          'sourcePath': sourcePath,
          'fileName': fileName,
          if (subDir != null) 'subDir': subDir,
        },
      );
      if (publicPath != null && publicPath.isNotEmpty) {
        // Source has been copied to public storage. Delete the temp copy so
        // we don't waste space inside the app's private external dir.
        try {
          final src = File(sourcePath);
          if (await src.exists()) await src.delete();
        } catch (_) {}
        return publicPath;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[receiver] publishToDownloads failed: $e');
      }
    }
    // Fallback: at least poke the media scanner so the file shows up in
    // gallery / file manager indexes.
    try {
      await _platform.invokeMethod<void>('scanFile', {'path': sourcePath});
    } catch (_) {}
    return null;
  }

  /// One-time connect tokens minted for QR payloads. Consumed on first
  /// use; holds at most the newest minted token so every previously
  /// displayed (screenshotted, shoulder-surfed) QR is dead.
  final Set<String> _connectTokens = {};

  /// Recently consumed connect tokens, kept briefly so a sender whose 200
  /// response was lost in transit (fresh hotspot join, TLS warm-up, radio
  /// power-save) can retry the SAME token instead of dying on 401 until
  /// the user restarts both apps. Keyed by token; the value pins the
  /// remote IP that consumed it plus an expiry, so only the original
  /// redeemer — and only for a short window — may replay.
  final Map<String, _RedeemedToken> _redeemedTokens = {};

  /// How long a consumed connect token may be replayed by the same remote
  /// IP. Long enough to cover a couple of client-side retry attempts,
  /// short enough that a screenshotted QR stays effectively single-use.
  /// Injectable so tests can shrink it.
  final Duration connectTokenReplayGrace;

  /// Called after a connect token is successfully redeemed, so the UI can
  /// re-mint and keep the on-screen QR valid.
  void Function()? onConnectTokenRedeemed;

  /// Mints a fresh single-use connect token for embedding in a QR code,
  /// invalidating any previously minted token. The token is consumed by
  /// the first successful call to the [LanLinkProtocol.routeConnect]
  /// route; replays (and all older tokens) get 401.
  String issueConnectToken() {
    final token = _uuid.v4();
    _connectTokens
      ..clear()
      ..add(token);
    _pruneRedeemedTokens();
    return token;
  }

  void _pruneRedeemedTokens({DateTime? now}) {
    final t = now ?? DateTime.now();
    _redeemedTokens.removeWhere((_, v) => t.isAfter(v.expires));
  }

  /// Whether [token] is still redeemable (i.e. it is the newest minted,
  /// not-yet-consumed connect token).
  bool isConnectTokenValid(String token) => _connectTokens.contains(token);

  Future<Response> _handleConnect(Request req) async {
    final token = req.url.queryParameters['token'];
    if (token == null || token.isEmpty) {
      return Response.badRequest(body: 'missing token');
    }
    final connInfo0 =
        req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final remoteIp = connInfo0?.remoteAddress.address ?? '';
    _pruneRedeemedTokens();
    final fresh = _connectTokens.remove(token);
    if (!fresh) {
      // Grace replay: the original redeemer retrying because our earlier
      // 200 never reached it. Anyone else (or an expired retry) gets 401.
      final redeemed = _redeemedTokens[token];
      final sameCaller = redeemed != null &&
          redeemed.remoteIp.isNotEmpty &&
          redeemed.remoteIp == remoteIp;
      if (!sameCaller) {
        return Response(401, body: 'invalid or already-used connect token');
      }
    } else {
      _redeemedTokens[token] = _RedeemedToken(
        remoteIp: remoteIp,
        expires: DateTime.now().add(connectTokenReplayGrace),
      );
      // Token consumed: let the UI re-mint so the displayed QR stays valid.
      onConnectTokenRedeemed?.call();
    }
    // Token accepted (and consumed): behave like /info so the caller learns
    // who we are, and surface the caller as a peer like /register does.
    // Read outside the try: an oversized body aborts via a shelf
    // HijackException that must propagate, not be swallowed below.
    final body = await _readBoundedControlBody(req, _maxDeviceInfoBodyBytes);
    try {
      if (body.isNotEmpty) {
        final decoded = json.decode(body);
        if (decoded is Map<String, dynamic>) {
          final connInfo =
              req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
          final ip = connInfo?.remoteAddress.address;
          if (ip != null && ip.isNotEmpty) {
            final caller = Device.fromJson(decoded, ip: ip);
            onPeerSeen?.call(caller);
            // Symmetric pairing (F3): the caller proved possession of our
            // one-time token, so trust it back — pin + link on our side
            // too, making "Send files" work in both directions without a
            // second scan.
            if (caller.fingerprint.isNotEmpty) {
              onPeerConnected?.call(caller);
            }
          }
        }
      }
    } catch (_) {
      // A malformed self-description is not fatal; the token was valid.
    }
    final me = localDeviceProvider();
    return Response.ok(
      json.encode(me.toJson()),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _handleCancel(Request req) async {
    final sessionId = req.url.queryParameters['sessionId'];
    if (sessionId == null) return Response.badRequest();
    final ps = _pending.remove(sessionId);
    if (ps != null) ps.session.markStatus(TransferStatus.cancelled);
    return Response.ok('ok');
  }

  /// F3 Disconnect: the peer is ending the pairing. The body carries the
  /// caller's device info (bounded like every control route). Whether the
  /// disconnect is honoured is decided by [onPeerDisconnected] — the app
  /// layer checks the fingerprint belongs to a currently linked peer (and
  /// that the caller's address matches), so a stranger on the LAN cannot
  /// tear down someone else's session with a spoofed fingerprint.
  Future<Response> _handleDisconnect(Request req) async {
    // Read outside the try: an oversized body aborts via a shelf
    // HijackException that must propagate, not be swallowed below.
    final body = await _readBoundedControlBody(req, _maxDeviceInfoBodyBytes);
    Device? caller;
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        final connInfo =
            req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
        final ip = connInfo?.remoteAddress.address;
        if (ip != null && ip.isNotEmpty) {
          caller = Device.fromJson(decoded, ip: ip);
        }
      }
    } catch (_) {
      // Falls through to the bad-request below.
    }
    if (caller == null || caller.fingerprint.isEmpty) {
      return Response.badRequest(body: 'missing device info');
    }
    final accepted = onPeerDisconnected?.call(caller) ?? false;
    if (!accepted) {
      return Response.forbidden('not a linked peer');
    }
    // Kill this peer's live receive sessions so its upload tokens are dead.
    dropSessionsForPeer(caller.fingerprint);
    return Response.ok('ok');
  }

  /// Cancels and forgets every pending receive session belonging to
  /// [fingerprint]: their single-use upload tokens die with the session and
  /// any in-flight upload is rejected mid-stream (the streaming handler
  /// aborts as soon as the session leaves the active state).
  void dropSessionsForPeer(String fingerprint) {
    if (fingerprint.isEmpty) return;
    final ids = _pending.entries
        .where((e) => e.value.session.peer.fingerprint == fingerprint)
        .map((e) => e.key)
        .toList();
    for (final id in ids) {
      final ps = _pending.remove(id);
      ps?.session.markStatus(TransferStatus.cancelled);
    }
  }

  /// Where partial data for [info] accumulates between attempts. Keyed by
  /// the sender's fingerprint + sanitized file name + size inside a hidden
  /// subfolder of the save dir, so a fresh session for the same file from
  /// the same peer finds the earlier bytes (sender file ids are re-minted
  /// per pick, so they can't key resume), while two peers concurrently
  /// sending an identically named file can never write into each other's
  /// part file.
  Future<File> _partFileFor(
      Directory saveDir, Device peer, FileInfo info) async {
    if (!_partsPruned) {
      _partsPruned = true;
      unawaited(prunePartFiles(saveDir));
    }
    final partsDir = Directory(p.join(saveDir.path, '.lanlink_parts'));
    await partsDir.create(recursive: true);
    final unsafe = RegExp(r'[\\/:*?"<>|]');
    // Clamp + strip control chars so a hostile fileName can neither exceed
    // the filesystem's 255-byte name limit (ENAMETOOLONG at openWrite) nor
    // embed invisible characters into the staging name.
    final safe = clampFileNameSegment(
      info.fileName
          .replaceAll(RegExp(r'[\x00-\x1f]'), '')
          .replaceAll(unsafe, '_'),
      maxBytes: 160,
    );
    var fp = peer.fingerprint.replaceAll(unsafe, '_');
    if (fp.length > 16) fp = fp.substring(0, 16);
    if (fp.isEmpty) fp = 'anon';
    return File(p.join(partsDir.path, '$fp.$safe.${info.size}.part'));
  }

  /// Paths handed out by [uniqueOutputPath] whose rename has not completed
  /// yet. With pipelined parallel uploads, two same-named files can both
  /// pass the on-disk existence check before either rename lands; the
  /// synchronous check-and-add on this set is what makes the reservation
  /// race-free within the event loop.
  final Set<String> _reservedPaths = {};

  @visibleForTesting
  Future<String> uniqueOutputPath(Directory dir, String fileName) async {
    final base = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    String candidate = p.join(dir.path, fileName);
    int i = 1;
    while (true) {
      // (A legacy `$candidate.lanlink-part` sibling probe used to sit here;
      // part files have lived under `.lanlink_parts/` for several releases,
      // so the extra stat per candidate was pure waste.)
      final taken = await File(candidate).exists() ||
          // No await between this check and the add below: reservation is
          // atomic within the event loop.
          !_reservedPaths.add(candidate);
      if (!taken) return candidate;
      if (i > 9999) {
        candidate = p.join(
          dir.path,
          '$base-${Random().nextInt(1 << 32).toRadixString(36)}$ext',
        );
        _reservedPaths.add(candidate);
        return candidate;
      }
      candidate = p.join(dir.path, '$base ($i)$ext');
      i++;
    }
  }

  /// Releases a reservation once the file exists on disk (or the write
  /// failed and the path will not be used).
  void _releaseReservedPath(String? path) {
    if (path != null) _reservedPaths.remove(path);
  }
}

class _PendingSession {
  _PendingSession({
    required this.session,
    required this.tokens,
    required this.files,
  });

  final TransferSession session;
  final Map<String, String> tokens;
  final Map<String, FileInfo> files;

  /// Upload tokens that have already begun a write. Single-use: a second
  /// request presenting the same token is rejected with 401.
  final Set<String> consumedTokens = {};

  /// Last time the sender showed signs of life (session creation, an
  /// upload call, bytes arriving). Read by the idle reaper.
  DateTime lastActivity = DateTime.now();

  void touch() => lastActivity = DateTime.now();
}

/// Internal control-flow signal: the session left the active state while an
/// upload was streaming in, so the write must stop immediately.
class _SessionNoLongerActive implements Exception {
  const _SessionNoLongerActive();
}

/// Bookkeeping for a consumed connect token still inside its replay-grace
/// window (see [Receiver.connectTokenReplayGrace]).
class _RedeemedToken {
  const _RedeemedToken({required this.remoteIp, required this.expires});

  final String remoteIp;
  final DateTime expires;
}
