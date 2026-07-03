/// Display models for the LanLink v4 component library.
///
/// This file is the interface contract between the design-system stage and
/// the app-shell stage: every v4 component consumes only these plain Dart
/// values plus callbacks. No imports from `lib/state/` or `lib/core/` are
/// allowed anywhere in `lib/ui/v4/`.
///
/// All strings arrive pre-humanized: device NAMES (never IP:port), sizes in
/// human units ("1.2 GB"), speeds as "34 MB/s", ETAs as "about 2 min left".
library;

import 'package:flutter/foundation.dart';

/// The kind of device a peer is, used only to pick an icon.
enum DeviceType { phone, tablet, laptop, desktop }

/// Lifecycle of a transfer session as the UI needs to distinguish it.
enum SessionStatus {
  /// Waiting for the other side to accept.
  waiting,

  /// Bytes are moving.
  transferring,

  /// Terminal: everything arrived.
  sent,

  /// Terminal: something went wrong.
  failed,

  /// Terminal: a human stopped it.
  cancelled,
}

/// Whether a [SessionStatus] is one of the three terminal states.
extension SessionStatusX on SessionStatus {
  bool get isTerminal =>
      this == SessionStatus.sent ||
      this == SessionStatus.failed ||
      this == SessionStatus.cancelled;
}

/// A peer shown on the device radar / device list.
///
/// Carries only what the radar renders — a friendly [name] (e.g.
/// "Purple-Otter"), a [deviceType] for the icon, and whether the peer is
/// [verified] (previously paired) — plus an opaque [id] the shell uses to
/// resolve a tap back to the right peer. The radar never renders the id,
/// and it deliberately has no address or port fields.
@immutable
class RadarPeerData {
  const RadarPeerData({
    required this.id,
    required this.name,
    required this.deviceType,
    this.verified = false,
  });

  /// Opaque stable identifier for tap resolution (e.g. a fingerprint).
  /// Never rendered; display names are NOT unique and must not be used as
  /// lookup keys.
  final String id;

  /// Friendly device name, e.g. "Purple-Otter". Never an IP or host:port.
  final String name;

  /// Device kind, used to pick the small type icon on the bubble.
  final DeviceType deviceType;

  /// True if this peer was verified on a previous session; shows a badge.
  final bool verified;

  @override
  bool operator ==(Object other) =>
      other is RadarPeerData &&
      other.id == id &&
      other.name == name &&
      other.deviceType == deviceType &&
      other.verified == verified;

  @override
  int get hashCode => Object.hash(id, name, deviceType, verified);
}

/// Which way a transfer session moves, as the UI needs it for wording
/// ("Sending" vs "Receiving", "to X" vs "from X").
enum SessionDirection { send, receive }

/// Everything a [SessionCard] renders about one transfer session.
///
/// All display strings are pre-formatted by the caller; the card does no
/// math and no formatting of raw bytes/seconds.
@immutable
class SessionCardData {
  const SessionCardData({
    required this.title,
    required this.totalSize,
    required this.status,
    this.direction = SessionDirection.send,
    this.fileCount = 1,
    this.peerName,
    this.progress,
    this.speed,
    this.eta,
    this.errorHint,
  });

  /// Which way the bytes move; picks direction-aware labels
  /// ("Receiving"/"Received!"/"from X" for [SessionDirection.receive]).
  final SessionDirection direction;

  /// Primary label: a filename ("holiday.mp4") or a bundle summary
  /// ("14 photos").
  final String title;

  /// Number of files in the session; used for the subtitle wording.
  final int fileCount;

  /// Human-readable total size, e.g. "1.2 GB".
  final String totalSize;

  /// Friendly name of the other device, e.g. "Purple-Otter". Optional.
  final String? peerName;

  /// Current lifecycle state; decides chip, colors, and visible actions.
  final SessionStatus status;

  /// 0.0–1.0 while [SessionStatus.transferring]; null shows an
  /// indeterminate bar while [SessionStatus.waiting].
  final double? progress;

  /// Live speed, pre-formatted, e.g. "34 MB/s". Shown while transferring.
  final String? speed;

  /// Live ETA, pre-formatted, e.g. "about 2 min left". Shown while
  /// transferring.
  final String? eta;

  /// One friendly sentence explaining a failure, e.g. "The connection was
  /// lost." Shown only when [status] is [SessionStatus.failed].
  final String? errorHint;
}

/// Everything the consent sheet renders about an incoming offer.
///
/// Intentionally hash-free: trust is communicated by [verified] (rendered
/// as a badge), never by fingerprints.
@immutable
class ConsentRequestData {
  const ConsentRequestData({
    required this.senderName,
    required this.fileCount,
    required this.totalSize,
    this.verified = false,
    this.previewFileNames = const [],
  });

  /// Friendly name of the sender, e.g. "Purple-Otter".
  final String senderName;

  /// How many files they want to send.
  final int fileCount;

  /// Human-readable total size, e.g. "48 MB".
  final String totalSize;

  /// True if the sender was verified on a previous session; shows a badge.
  final bool verified;

  /// Up to a few filenames to preview (the sheet truncates the rest).
  final List<String> previewFileNames;
}
