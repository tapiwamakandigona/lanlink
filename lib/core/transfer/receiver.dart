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
  });

  /// Returns the current local-device info (alias, port, fingerprint, etc.).
  /// We accept it as a provider so settings changes take effect without
  /// restarting the server.
  final Device Function() localDeviceProvider;

  /// Returns the directory to save incoming files into.
  final Future<Directory> Function() saveDirProvider;

  final AcceptHandler onAccept;
  final SessionStartedHandler onSessionStarted;

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
    _httpServer =
        await shelf_io.serve(handler, InternetAddress.anyIPv4, desired);
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
    // Drain the body for protocol compliance; we don't currently use it.
    try {
      await req.readAsString();
    } catch (_) {}
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

    return Response.ok(
      json.encode({'sessionId': sessionId, 'files': tokens}),
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
    await saveDir.create(recursive: true);
    final finalPath = await _uniqueOutputPath(saveDir, info.fileName);
    final tmpPath = '$finalPath.lanlink-part';
    final tmpFile = File(tmpPath);
    final sink = tmpFile.openWrite();

    int received = 0;
    try {
      await for (final chunk in req.read()) {
        sink.add(chunk);
        received += chunk.length;
        ps.session.updateBytes(fileId, received);
      }
      await sink.flush();
      await sink.close();
      await tmpFile.rename(finalPath);
      await _makeAndroidFileVisible(finalPath);
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        if (await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {}
      ps.session.markFile(fileId, TransferStatus.failed, error: '$e');
      ps.session.markStatus(TransferStatus.failed);
      return Response.internalServerError(body: 'write failed: $e');
    }

    ps.session.markFile(fileId, TransferStatus.completed, savedPath: finalPath);

    // If every file in the session is done, mark the session complete.
    final allDone = ps.session.files.values
        .every((f) => f.status == TransferStatus.completed);
    if (allDone) {
      ps.session.markStatus(TransferStatus.completed);
      _pending.remove(sessionId);
    }
    return Response.ok('ok');
  }

  Future<void> _makeAndroidFileVisible(String path) async {
    if (!Platform.isAndroid) return;
    try {
      await _platform.invokeMethod<void>('scanFile', {'path': path});
    } catch (_) {}
  }

  Future<Response> _handleCancel(Request req) async {
    final sessionId = req.url.queryParameters['sessionId'];
    if (sessionId == null) return Response.badRequest();
    final ps = _pending.remove(sessionId);
    if (ps != null) ps.session.markStatus(TransferStatus.cancelled);
    return Response.ok('ok');
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
