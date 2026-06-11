import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
  });

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

  HttpServer? _httpServer;
  final _uuid = const Uuid();
  static const _platform = MethodChannel('lanlink/received_files');

  /// Active receive sessions, keyed by sessionId.
  final Map<String, _PendingSession> _pending = {};

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
      ..post(LanLinkProtocol.routeCancel, _handleCancel);

    final handler =
        const Pipeline().addMiddleware(_logging()).addHandler(router.call);

    final desired = localDeviceProvider().port;
    _httpServer = await _bindWithFallback(handler, desired);
  }

  /// Binds the HTTP server on [desired], falling back to nearby ports and
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
        final server =
            await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
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
    try {
      final body = await req.readAsString();
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
    Map<String, dynamic> body;
    try {
      body = json.decode(await req.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      return Response.badRequest(body: 'invalid json: $e');
    }
    final info = body['info'] as Map<String, dynamic>?;
    final filesRaw = body['files'] as Map<String, dynamic>?;
    if (info == null || filesRaw == null) {
      return Response.badRequest(body: 'missing info or files');
    }

    final peerIp =
        (req.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address ??
            '0.0.0.0';
    final peer = Device.fromJson(info, ip: peerIp);
    final files = filesRaw.values
        .map((e) => FileInfo.fromJson(e as Map<String, dynamic>))
        .toList();

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
        final part = await _partFileFor(saveDir, f);
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

    final saveDir = await saveDirProvider();
    try {
      await saveDir.create(recursive: true);
    } catch (e) {
      ps.session.markFile(fileId, TransferStatus.failed,
          error: 'Cannot create save folder ${saveDir.path}: $e');
      ps.session.markStatus(TransferStatus.failed);
      return Response.internalServerError(
          body: 'cannot create save folder: $e');
    }

    // Resume support: the sender may continue an interrupted upload at the
    // byte offset we advertised in prepare-upload. The offset must match
    // the part file exactly — otherwise the sender restarts from zero.
    final offset = int.tryParse(req.url.queryParameters['offset'] ?? '0') ?? 0;
    final partFile = await _partFileFor(saveDir, info);
    if (offset > 0) {
      final have = await partFile.exists() ? await partFile.length() : 0;
      if (have != offset) {
        return Response(
          409,
          body: 'offset mismatch: receiver has $have bytes',
        );
      }
    }

    IOSink? sink;
    try {
      sink = partFile.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
    } catch (e) {
      ps.session.markFile(fileId, TransferStatus.failed,
          error: 'Cannot open ${partFile.path}: $e');
      ps.session.markStatus(TransferStatus.failed);
      return Response.internalServerError(body: 'cannot open temp file: $e');
    }

    int received = offset;
    String finalPath;
    try {
      await for (final chunk in req.read()) {
        sink.add(chunk);
        received += chunk.length;
        ps.session.updateBytes(fileId, received);
      }
      await sink.flush();
      await sink.close();
      finalPath = await _uniqueOutputPath(saveDir, info.fileName);
      await partFile.rename(finalPath);
    } catch (e) {
      // Keep the part file: whatever made it to disk is the head start for
      // the next attempt.
      try {
        await sink.close();
      } catch (_) {}
      ps.session.markFile(fileId, TransferStatus.failed, error: '$e');
      ps.session.markStatus(TransferStatus.failed);
      return Response.internalServerError(body: 'write failed: $e');
    }

    // On Android, the path we just wrote to is almost always inside the app's
    // private external files directory (because scoped storage blocks direct
    // writes to /storage/emulated/0/Download from API 30+). Publish a copy to
    // MediaStore.Downloads so the file is visible to the user in the Files /
    // Downloads app exactly like ShareIt / LocalSend.
    final publicLocation = await _publishToPublicDownloads(
      sourcePath: finalPath,
      fileName: info.fileName,
    );
    final visiblePath = publicLocation ?? finalPath;
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
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final publicPath = await _platform.invokeMethod<String>(
        'publishToDownloads',
        {'sourcePath': sourcePath, 'fileName': fileName},
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

  Future<Response> _handleCancel(Request req) async {
    final sessionId = req.url.queryParameters['sessionId'];
    if (sessionId == null) return Response.badRequest();
    final ps = _pending.remove(sessionId);
    if (ps != null) ps.session.markStatus(TransferStatus.cancelled);
    return Response.ok('ok');
  }

  /// Where partial data for [info] accumulates between attempts. Keyed by
  /// sanitized file name + size inside a hidden subfolder of the save dir,
  /// so a fresh session for the same file finds the earlier bytes.
  Future<File> _partFileFor(Directory saveDir, FileInfo info) async {
    final partsDir = Directory(p.join(saveDir.path, '.lanlink_parts'));
    await partsDir.create(recursive: true);
    final safe = info.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File(p.join(partsDir.path, '$safe.${info.size}.part'));
  }

  Future<String> _uniqueOutputPath(Directory dir, String fileName) async {
    final base = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    String candidate = p.join(dir.path, fileName);
    int i = 1;
    while (await File(candidate).exists() ||
        await File('$candidate.lanlink-part').exists()) {
      candidate = p.join(dir.path, '$base ($i)$ext');
      i++;
      if (i > 9999) {
        candidate = p.join(
          dir.path,
          '$base-${Random().nextInt(1 << 32).toRadixString(36)}$ext',
        );
        break;
      }
    }
    return candidate;
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
}
