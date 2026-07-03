import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/platform/media_library.dart';
import 'package:lanlink/core/platform/media_permissions.dart';
import 'package:permission_handler/permission_handler.dart';

/// Fake requester that answers each permission from a canned status map
/// and records every batch it is asked for, so tests can assert both the
/// verdict and the request order (granular first, legacy second).
class _FakeRequester {
  _FakeRequester(this.statuses);

  final Map<Permission, PermissionStatus> statuses;
  final batches = <List<Permission>>[];

  Future<Map<Permission, PermissionStatus>> call(
    List<Permission> permissions,
  ) async {
    batches.add(permissions);
    return {
      for (final p in permissions) p: statuses[p] ?? PermissionStatus.denied,
    };
  }
}

void main() {
  tearDown(() {
    MediaPermissions.debugForceSupported = false;
    MediaPermissions.debugRequester = null;
    MediaPermissions.debugOpenSettings = null;
    MediaLibrary.debugForceSupported = false;
  });

  _FakeRequester install(Map<Permission, PermissionStatus> statuses) {
    MediaPermissions.debugForceSupported = true;
    final fake = _FakeRequester(statuses);
    MediaPermissions.debugRequester = fake.call;
    return fake;
  }

  test('unsupported platform never requests anything', () async {
    // No debugForceSupported: host test runner is not Android.
    final fake = _FakeRequester({});
    MediaPermissions.debugRequester = fake.call;

    expect(await MediaPermissions.request(), MediaAccess.unsupported);
    expect(fake.batches, isEmpty);
  });

  group('Android 13+ branch (granular READ_MEDIA_* live)', () {
    test('any granular grant is enough; legacy storage never requested',
        () async {
      final fake = install({
        Permission.photos: PermissionStatus.granted,
        Permission.videos: PermissionStatus.denied,
        Permission.audio: PermissionStatus.denied,
      });

      expect(await MediaPermissions.request(), MediaAccess.granted);
      expect(fake.batches, hasLength(1));
      expect(
        fake.batches.single,
        [Permission.photos, Permission.videos, Permission.audio],
      );
    });

    test('limited access (Android 14 "selected photos") counts as granted',
        () async {
      install({Permission.photos: PermissionStatus.limited});

      expect(await MediaPermissions.request(), MediaAccess.granted);
    });

    test('denied once stays denied (re-request possible)', () async {
      // Storage resolves to plain denied on 33+ (maxSdkVersion stripped),
      // so the verdict must stay `denied`, not `permanentlyDenied`.
      final fake = install({});

      expect(await MediaPermissions.request(), MediaAccess.denied);
      expect(fake.batches, hasLength(2));
      expect(fake.batches.last, [Permission.storage]);
    });

    test('permanently denied maps to permanentlyDenied', () async {
      install({
        Permission.photos: PermissionStatus.permanentlyDenied,
        Permission.videos: PermissionStatus.permanentlyDenied,
        Permission.audio: PermissionStatus.permanentlyDenied,
      });

      expect(
        await MediaPermissions.request(),
        MediaAccess.permanentlyDenied,
      );
    });
  });

  group('Android ≤32 branch (granular groups inert, storage live)', () {
    test('storage grant wins after inert granular batch', () async {
      // On ≤32 permission_handler resolves photos/videos/audio to plain
      // denied without a prompt; the legacy storage request is the one
      // that shows the sheet.
      final fake = install({Permission.storage: PermissionStatus.granted});

      expect(await MediaPermissions.request(), MediaAccess.granted);
      expect(fake.batches, hasLength(2));
      expect(fake.batches.last, [Permission.storage]);
    });

    test('storage permanently denied maps to permanentlyDenied', () async {
      install({Permission.storage: PermissionStatus.permanentlyDenied});

      expect(
        await MediaPermissions.request(),
        MediaAccess.permanentlyDenied,
      );
    });
  });

  test('a throwing platform call reports denied, never granted', () async {
    MediaPermissions.debugForceSupported = true;
    MediaPermissions.debugRequester = (_) async => throw StateError('boom');

    expect(await MediaPermissions.request(), MediaAccess.denied);
  });

  test('openSettings delegates to the injected deep link', () async {
    var opened = false;
    MediaPermissions.debugOpenSettings = () async {
      opened = true;
      return true;
    };

    expect(await MediaPermissions.openSettings(), isTrue);
    expect(opened, isTrue);
  });

  test('MediaLibrary.ensurePermission is a thin bool view of the gate',
      () async {
    install({Permission.photos: PermissionStatus.granted});
    expect(await MediaLibrary.ensurePermission(), isTrue);

    install({});
    expect(await MediaLibrary.ensurePermission(), isFalse);
  });
}
