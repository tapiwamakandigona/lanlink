// Ghost-peer pruning: devices that left the network must drop off the
// Send radar after AppState.peerTtl instead of lingering as
// guaranteed-timeout targets. Peers with a live session are kept even in
// radio silence (sweeps pause during transfers).

import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/core/models/device.dart';
import 'package:lanlink/core/models/file_info.dart';
import 'package:lanlink/core/models/session.dart';
import 'package:lanlink/core/protocol/constants.dart';
import 'package:lanlink/core/settings/app_settings.dart';
import 'package:lanlink/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Device _peer(String fp) => Device(
      alias: 'peer-$fp',
      version: LanLinkProtocol.protocolVersion,
      deviceModel: 'test',
      deviceType: LanLinkProtocol.deviceTypeHeadless,
      fingerprint: fp,
      port: LanLinkProtocol.defaultPort,
      protocol: 'http',
      ip: '192.168.1.50',
    );

Future<AppState> _state() async {
  SharedPreferences.setMockInitialValues({});
  return AppState.forScreenshots(settings: await AppSettings.load());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('peers older than peerTtl are pruned, fresh ones stay', () async {
    final state = await _state();
    state.debugPeerSeen(_peer('old'));
    state.debugPeerSeen(_peer('fresh'));
    expect(state.peers.keys, containsAll(['old', 'fresh']));

    // "old" was last seen just beyond the TTL, "fresh" just within it.
    final now = DateTime.now().add(
      AppState.peerTtl + const Duration(seconds: 1),
    );
    // Re-observe fresh at a later point by touching it again first.
    state.debugPeerSeen(_peer('fresh'));

    var notified = 0;
    state.addListener(() => notified++);
    state.prunePeersNow(now: now);
    expect(state.peers.containsKey('old'), isFalse,
        reason: 'silent for > peerTtl — gone');
    // Both were seen "now-ish" in wall-clock terms; only distinguish via
    // the shifted clock: fresh was also seen before cutoff, so it is
    // pruned too unless re-seen. Re-add and verify a fresh peer survives
    // a prune with the real clock.
    state.debugPeerSeen(_peer('fresh'));
    state.prunePeersNow();
    expect(state.peers.containsKey('fresh'), isTrue,
        reason: 'seen milliseconds ago — must survive');
    expect(notified, greaterThan(0));
  });

  test('peers with a live session survive pruning in radio silence', () async {
    final state = await _state();
    state.debugPeerSeen(_peer('busy'));
    final file = FileInfo(
      id: 'f1',
      fileName: 'a.bin',
      size: 10,
      fileType: 'other',
    );
    state.seedForScreenshots(sessions: [
      TransferSession(
        sessionId: 's1',
        direction: TransferDirection.send,
        peer: _peer('busy'),
        files: {
          'f1': FileProgress(file: file, status: TransferStatus.transferring),
        },
        status: TransferStatus.transferring,
      ),
    ]);

    final farFuture = DateTime.now().add(const Duration(hours: 1));
    state.prunePeersNow(now: farFuture);
    expect(state.peers.containsKey('busy'), isTrue,
        reason: 'sweeps pause during transfers; silence while bytes flow '
            'is expected, not absence');
  });

  test('terminal sessions do not protect their peer', () async {
    final state = await _state();
    state.debugPeerSeen(_peer('done'));
    final file = FileInfo(
      id: 'f1',
      fileName: 'a.bin',
      size: 10,
      fileType: 'other',
    );
    state.seedForScreenshots(sessions: [
      TransferSession(
        sessionId: 's1',
        direction: TransferDirection.send,
        peer: _peer('done'),
        files: {
          'f1': FileProgress(file: file, status: TransferStatus.completed),
        },
        status: TransferStatus.completed,
      ),
    ]);

    final farFuture = DateTime.now().add(const Duration(hours: 1));
    state.prunePeersNow(now: farFuture);
    expect(state.peers.containsKey('done'), isFalse);
  });
}
