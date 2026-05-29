import 'dart:convert';

import '../models/session.dart';
import '../util/pairing_guide.dart';

/// A single user pick from the launch-time pairing wizard. We remember
/// it so the next launch can offer a "Same as last time" shortcut.
class PairingChoice {
  const PairingChoice({
    required this.direction,
    required this.other,
  });

  final TransferDirection direction;
  final OtherDeviceKind other;

  Map<String, dynamic> toJson() => {
        'direction': direction.name,
        'other': other.name,
      };

  static PairingChoice? fromJson(Map<String, dynamic> json) {
    final d = json['direction'];
    final o = json['other'];
    if (d is! String || o is! String) return null;
    final direction = TransferDirection.values.firstWhere(
      (v) => v.name == d,
      orElse: () => TransferDirection.send,
    );
    final other = OtherDeviceKind.values.firstWhere(
      (v) => v.name == o,
      orElse: () => OtherDeviceKind.notSure,
    );
    return PairingChoice(direction: direction, other: other);
  }

  /// Decode a stored JSON blob (as written by [encode]) back into a
  /// [PairingChoice]; returns null on any parse error.
  static PairingChoice? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return null;
      return fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  String encode() => json.encode(toJson());

  /// Short, friendly summary like "Sending to an iPhone" used in the
  /// "Same as last time" suggestion card on the wizard's first step.
  String get summary {
    final verb =
        direction == TransferDirection.send ? 'Sending to' : 'Receiving from';
    return '$verb ${other.shortLabel}';
  }
}

extension OtherDeviceKindShortLabel on OtherDeviceKind {
  String get shortLabel {
    switch (this) {
      case OtherDeviceKind.android:
        return 'an Android phone';
      case OtherDeviceKind.iphone:
        return 'an iPhone';
      case OtherDeviceKind.windows:
        return 'a Windows PC';
      case OtherDeviceKind.mac:
        return 'a Mac';
      case OtherDeviceKind.notSure:
        return 'another device';
    }
  }
}
