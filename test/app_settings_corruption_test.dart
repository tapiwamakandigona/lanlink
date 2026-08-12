import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('partially corrupt trust and pin lists retain valid fingerprints',
      () async {
    SharedPreferences.setMockInitialValues({
      'lanlink_trusted_fingerprints': json.encode([
        'trusted-a',
        7,
        null,
        '',
        'trusted-b',
      ]),
      'lanlink_pinned_fingerprints_v1': json.encode([
        'pinned-a',
        false,
        '',
        'pinned-b',
      ]),
    });

    final settings = await AppSettings.load();

    expect(settings.trustedFingerprints, {'trusted-a', 'trusted-b'});
    expect(settings.pinnedFingerprints, {'pinned-a', 'pinned-b'});
  });

  test('partially corrupt alias maps retain only string pairs', () async {
    SharedPreferences.setMockInitialValues({
      'lanlink_trusted_aliases': json.encode({
        'fp-a': 'Anna',
        'fp-number': 42,
        'fp-null': null,
      }),
      'lanlink_peer_nicknames': json.encode({
        'fp-b': 'Laptop',
        'fp-number': 42,
        'fp-null': null,
      }),
    });

    final settings = await AppSettings.load();

    expect(settings.trustedAliasFor('fp-a'), 'Anna');
    expect(settings.trustedAliasFor('fp-number'), isNull);
    expect(settings.peerNicknames, {'fp-b': 'Laptop'});
  });
}
