/// Pure mapping helpers between engine objects and the v4 display models.
///
/// Kept free of widgets so the mapping is unit-testable: everything the
/// shell renders goes through these functions.
library;

import '../../core/models/device.dart';
import '../../core/models/session.dart';
import '../../core/protocol/constants.dart';
import '../../core/settings/app_settings.dart';
import '../../core/util/eta.dart';
import '../../core/util/format.dart';
import '../v4/v4.dart' as v4;

/// Maps an engine [TransferStatus] to the v4 display status.
v4.SessionStatus displayStatus(TransferSession session) {
  switch (session.status) {
    case TransferStatus.awaitingAccept:
      return v4.SessionStatus.waiting;
    case TransferStatus.transferring:
      return v4.SessionStatus.transferring;
    case TransferStatus.completed:
      return v4.SessionStatus.sent;
    case TransferStatus.failed:
      return v4.SessionStatus.failed;
    case TransferStatus.cancelled:
      return v4.SessionStatus.cancelled;
  }
}

/// The peer name the shell shows: user nickname first, then the announced
/// alias, then a friendly fallback.
String displayPeerName(AppSettings settings, Device peer) {
  return settings.nicknameFor(peer.fingerprint) ??
      (peer.alias.trim().isEmpty ? 'Unnamed device' : peer.alias.trim());
}

/// Maps one engine session to everything a [v4.SessionCard] renders.
v4.SessionCardData sessionCardData(TransferSession session,
    {String? peerName}) {
  final files = session.files.values.toList();
  final status = displayStatus(session);
  final title = files.length == 1
      ? files.first.file.fileName
      : '${files.length} files';
  final transferring = status == v4.SessionStatus.transferring;
  final speed = session.speedBytesPerSec;
  String? errorHint;
  if (status == v4.SessionStatus.failed) {
    for (final f in files) {
      final e = f.error;
      if (e != null && e.trim().isNotEmpty) {
        errorHint = e;
        break;
      }
    }
    errorHint ??= 'Something went wrong during the transfer.';
  }
  final eta = transferring
      ? plainEnglishEta(
          totalBytes: session.totalBytes,
          doneBytes: session.transferredBytes,
          bytesPerSec: speed,
        )
      : '';
  return v4.SessionCardData(
    title: title,
    direction: session.direction == TransferDirection.receive
        ? v4.SessionDirection.receive
        : v4.SessionDirection.send,
    fileCount: files.length,
    totalSize: formatBytes(session.totalBytes),
    peerName: peerName,
    status: status,
    progress: transferring ? session.fraction.clamp(0.0, 1.0) : null,
    speed: transferring && speed > 0 ? formatSpeed(speed) : null,
    eta: eta.isEmpty ? null : eta,
    errorHint: errorHint,
  );
}

/// Maps an engine peer to a radar bubble. The verified flag MUST come from
/// a [Device] produced by AppState's peer pipeline (`AppState.peers`).
v4.RadarPeerData radarPeerData(AppSettings settings, Device peer) {
  return v4.RadarPeerData(
    id: peer.fingerprint,
    name: displayPeerName(settings, peer),
    deviceType: peer.deviceType == LanLinkProtocol.deviceTypeMobile
        ? v4.DeviceType.phone
        : v4.DeviceType.laptop,
    verified: peer.verified,
  );
}

/// One visual unit on the home screen: either a lone session or all the
/// sessions sharing a groupId (the "+ Add files" cluster).
class SessionCluster {
  SessionCluster({required this.groupId, required this.sessions});

  /// Null for standalone sessions.
  final String? groupId;

  /// Newest first, matching `visibleSessions` order.
  final List<TransferSession> sessions;
}

/// Groups [visibleSessions] into clusters, preserving overall order: a
/// cluster sits where its newest member sits.
List<SessionCluster> clusterSessions(List<TransferSession> visibleSessions) {
  final clusters = <SessionCluster>[];
  final byGroup = <String, SessionCluster>{};
  for (final s in visibleSessions) {
    final gid = s.groupId;
    if (gid == null) {
      clusters.add(SessionCluster(groupId: null, sessions: [s]));
      continue;
    }
    final existing = byGroup[gid];
    if (existing != null) {
      existing.sessions.add(s);
    } else {
      final cluster = SessionCluster(groupId: gid, sessions: [s]);
      byGroup[gid] = cluster;
      clusters.add(cluster);
    }
  }
  return clusters;
}
