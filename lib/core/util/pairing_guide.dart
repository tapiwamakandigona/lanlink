import '../models/session.dart';

/// The kind of device on the *other* end of a transfer, as picked by the
/// user in the "Get connected" guide. We already know our own platform from
/// `Platform.is*`, so self + direction + this resolves to concrete steps.
enum OtherDeviceKind { android, iphone, windows, mac, notSure }

/// Coarse classification of *this* device's platform, independent of
/// `dart:io` so the resolver stays unit-testable.
enum SelfPlatform { android, ios, windows, macos, linux, other }

extension OtherDeviceKindLabel on OtherDeviceKind {
  String get label {
    switch (this) {
      case OtherDeviceKind.android:
        return 'Android phone / tablet';
      case OtherDeviceKind.iphone:
        return 'iPhone / iPad';
      case OtherDeviceKind.windows:
        return 'Windows PC';
      case OtherDeviceKind.mac:
        return 'Mac';
      case OtherDeviceKind.notSure:
        return 'Not sure';
    }
  }
}

/// Concrete, user-facing instructions for one pairing. [steps] are written in
/// the second person ("you") for the device the user is holding.
class PairingGuide {
  const PairingGuide({
    required this.title,
    required this.steps,
    this.tip,
  });

  final String title;
  final List<String> steps;
  final String? tip;
}

bool _isMobile(SelfPlatform p) =>
    p == SelfPlatform.android || p == SelfPlatform.ios;

bool _isAndroid(SelfPlatform p) => p == SelfPlatform.android;

bool _otherIsMobile(OtherDeviceKind k) =>
    k == OtherDeviceKind.android || k == OtherDeviceKind.iphone;

/// Resolves tailored connection steps. The headline real-world case is
/// phone-to-phone over a hotspot; everything else falls back to same-Wi-Fi
/// auto-discovery, which "just works" once both devices are on one network.
PairingGuide resolvePairingGuide({
  required SelfPlatform self,
  required TransferDirection direction,
  required OtherDeviceKind other,
}) {
  final sending = direction == TransferDirection.send;

  if (other == OtherDeviceKind.notSure) {
    return const PairingGuide(
      title: 'Connect any two devices',
      steps: [
        'If both devices are on the same Wi-Fi, just open LanLink on both — '
            'they find each other automatically. Then pick files and tap the '
            'other device.',
        'No shared Wi-Fi? On an Android phone, open Receive and switch to '
            '"No shared Wi-Fi" — it starts a direct link the other device '
            'joins by scanning the QR.',
      ],
      tip: 'When in doubt, get both devices onto the same Wi-Fi first — that '
          'is always the simplest path.',
    );
  }

  // Both ends are desktops (or one desktop + a phone on shared Wi-Fi):
  // LAN auto-discovery is the clean path, no QR needed.
  final bothDesktop = !_isMobile(self) && !_otherIsMobile(other);
  if (bothDesktop) {
    return PairingGuide(
      title: sending ? 'Send over Wi-Fi' : 'Receive over Wi-Fi',
      steps: const [
        'Make sure both computers are on the same Wi-Fi network.',
        'Open LanLink on both — each one appears in the other\'s '
            '"Nearby devices" list within a few seconds.',
        'Pick your files with "Add", then tap the other computer to send. '
            'They accept the prompt and the transfer starts.',
      ],
      tip: 'On desktop you can also drag files onto the window to stage them.',
    );
  }

  // A phone is involved. Decide who hosts the hotspot.
  // Android can host a hotspot; iOS cannot do so from inside the app.
  final phonePresent = _isMobile(self) || _otherIsMobile(other);
  if (phonePresent) {
    final iAmAndroid = _isAndroid(self);
    final otherIsAndroid = other == OtherDeviceKind.android;

    // Prefer an Android device as the hotspot host.
    final iHost = iAmAndroid && !(otherIsAndroid && !sending);
    final hostIsAndroidSomewhere = iAmAndroid || otherIsAndroid;

    if (hostIsAndroidSomewhere) {
      if (iHost) {
        return PairingGuide(
          title: sending ? 'Send via your hotspot' : 'Receive via your hotspot',
          steps: [
            'Open Receive and switch to "No shared Wi-Fi" — LanLink starts '
                'a direct link hotspot for you, no settings needed.',
            if (sending)
              'Have them scan your QR: an Android phone hops onto your link '
                  'by itself; an iPhone or computer joins the network shown '
                  'under the code first.'
            else
              'Have them scan your QR (Android joins your link '
                  'automatically), then accept their files when the prompt '
                  'appears.',
          ],
          tip: 'The direct link is created in-app — you never have to touch '
              'Android\'s hotspot settings.',
        );
      }
      return PairingGuide(
        title: sending
            ? 'Send by joining their hotspot'
            : 'Receive on their hotspot',
        steps: [
          'Ask the other person (the Android device) to open Receive and '
              'switch to "No shared Wi-Fi" — LanLink starts a direct link '
              'hotspot for them.',
          if (self == SelfPlatform.android)
            'Scan their QR (Scan QR) — your phone joins their link '
                'automatically.'
          else
            'Join the network shown under their QR from your Wi-Fi '
                'settings, then scan the code (Scan QR).',
          if (sending)
            'Pick files and send.'
          else
            'They pick files and send; accept the prompt when it appears.',
        ],
      );
    }

    // Neither side is Android (e.g. iPhone <-> iPhone, or iPhone <-> Mac).
    return const PairingGuide(
      title: 'Connect without Android',
      steps: [
        'Easiest: put both devices on the same Wi-Fi network — they discover '
            'each other automatically, no QR needed.',
        'If there\'s no shared Wi-Fi, turn on Personal Hotspot on one iPhone '
            'from Control Center and join it from the other device.',
        'Then use Scan QR / Show QR to link the two and transfer.',
      ],
      tip: 'iPhones can\'t turn their hotspot on automatically, so you\'ll '
          'toggle Personal Hotspot yourself in Control Center.',
    );
  }

  // Fallback (should be unreachable): generic LAN guidance.
  return const PairingGuide(
    title: 'Connect over Wi-Fi',
    steps: [
      'Put both devices on the same Wi-Fi network and open LanLink on each.',
      'They appear in "Nearby devices" automatically — pick files and tap to '
          'send.',
    ],
  );
}
