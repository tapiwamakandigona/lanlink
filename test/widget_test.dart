// Basic smoke test — verifies the protocol constants and value classes
// behave as expected. We avoid spinning up a full app in widget tests
// because the bootstrap path needs platform plugins (shared_preferences,
// path_provider, etc.) that don't run in the pure VM test environment.

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/util/format.dart';

void main() {
  group('LanLinkProtocol', () {
    test('routes are namespaced under /api/localsend/v2', () {
      expect(LanLinkProtocol.routeInfo, '/api/localsend/v2/info');
      expect(LanLinkProtocol.routePrepareUpload,
          '/api/localsend/v2/prepare-upload');
      expect(LanLinkProtocol.routeUpload, '/api/localsend/v2/upload');
    });
    test('default port matches LocalSend convention', () {
      expect(LanLinkProtocol.defaultPort, 53317);
      expect(LanLinkProtocol.multicastGroup, '224.0.0.167');
    });
  });

  group('Device JSON round-trip', () {
    test('preserves alias / fingerprint / port', () {
      final dev = Device(
        alias: 'My Laptop',
        version: LanLinkProtocol.protocolVersion,
        deviceModel: 'Windows',
        deviceType: LanLinkProtocol.deviceTypeDesktop,
        fingerprint: 'abc-123',
        port: 53317,
        protocol: 'http',
        ip: '192.168.1.10',
      );
      final back = Device.fromJson(dev.toJson(), ip: '192.168.1.10');
      expect(back.alias, dev.alias);
      expect(back.fingerprint, dev.fingerprint);
      expect(back.port, dev.port);
      expect(back.deviceType, dev.deviceType);
    });
  });

  group('fileTypeForName', () {
    test('classifies common extensions', () {
      expect(fileTypeForName('photo.jpg'), 'image');
      expect(fileTypeForName('clip.mp4'), 'video');
      expect(fileTypeForName('install.apk'), 'app');
      expect(fileTypeForName('book.pdf'), 'pdf');
      expect(fileTypeForName('archive.zip'), 'archive');
      expect(fileTypeForName('notes.txt'), 'text');
      expect(fileTypeForName('random.xyz'), 'other');
    });
  });

  group('formatBytes', () {
    test('handles boundary cases', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    });
  });
}
