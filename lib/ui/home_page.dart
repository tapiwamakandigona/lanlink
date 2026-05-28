import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/connectivity/connectivity_mode.dart';
import '../core/models/device.dart';
import '../core/models/file_info.dart';
import '../core/platform/android_apps.dart';
import '../state/app_state.dart';
import 'about_page.dart';
import 'history_page.dart';
import 'scan_qr_page.dart';
import 'settings_page.dart';
import 'widgets/attribution_banner.dart';
import 'widgets/device_card.dart';
import 'widgets/pair_qr_sheet.dart';
import 'widgets/peer_action_sheet.dart';
import 'widgets/progress_card.dart';
import 'widgets/update_available_banner.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<FileInfo> _staged = [];
  final _uuid = const Uuid();
  final Set<String> _selectedFingerprints = <String>{};
  bool _multiSelect = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final mode = state.settings.connectivityMode;
    final peers = state.peers.values.toList()
      ..sort((a, b) => a.alias.compareTo(b.alias));
    final active = state.sessions
        .where((s) =>
            s.status.name == 'transferring' ||
            s.status.name == 'awaitingAccept')
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('LanLink'),
        actions: [
          IconButton(
            tooltip: state.isScanning ? 'Scanning…' : 'Rescan for devices',
            icon: state.isScanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: state.isScanning ? null : () => state.refreshDiscovery(),
          ),
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryPage()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                if (state.updateChecker.availableUpdate != null &&
                    state.settings.skippedUpdateVersion !=
                        state.updateChecker.availableUpdate!.tagName)
                  UpdateAvailableBanner(
                    release: state.updateChecker.availableUpdate!,
                    onDismiss: () => state.settings.setSkippedUpdateVersion(
                      state.updateChecker.availableUpdate!.tagName,
                    ),
                  ),
                _modePanel(context, state),
                if (mode == ConnectivityMode.hotspot) ...[
                  const SizedBox(height: 8),
                  _hotspotPanel(context, state),
                ],
                const SizedBox(height: 16),
                _stagedFilesPanel(context),
                const SizedBox(height: 16),
                _nearbyHeader(context, mode, peers.length),
                if (mode == ConnectivityMode.bluetooth)
                  _bluetoothPanel(context, state)
                else if (peers.isEmpty)
                  _emptyPeers(context, mode)
                else
                  ...peers.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DeviceCard(
                        device: p,
                        selected: _multiSelect &&
                            _selectedFingerprints.contains(p.fingerprint),
                        trailing: _multiSelect
                            ? Icon(
                                _selectedFingerprints.contains(p.fingerprint)
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          if (_multiSelect) {
                            _toggleSelection(p);
                          } else {
                            _sendStagedTo(p);
                          }
                        },
                        onLongPress: () => showPeerActionSheet(context, p),
                      ),
                    ),
                  ),
                if (active.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Active transfers',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...active.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ProgressCard(session: s),
                      )),
                ],
              ],
            ),
          ),
          const AttributionBanner(),
        ],
      ),
      floatingActionButton: _multiSelect
          ? FloatingActionButton.extended(
              onPressed:
                  _selectedFingerprints.isEmpty ? null : _sendStagedToSelected,
              icon: const Icon(Icons.send),
              label: Text(
                _selectedFingerprints.isEmpty
                    ? 'Pick devices'
                    : 'Send to ${_selectedFingerprints.length}',
              ),
            )
          : FloatingActionButton.extended(
              onPressed: _showAddMenu,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
    );
  }

  Future<void> _showAddMenu() async {
    final action = await showModalBottomSheet<_AddAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Add files'),
              subtitle: const Text('Pick documents, media, archives, or apps'),
              onTap: () => Navigator.of(context).pop(_AddAction.files),
            ),
            ListTile(
              leading: const Icon(Icons.android),
              title: const Text('Add installed apps as APKs'),
              subtitle: const Text('Android only'),
              onTap: () => Navigator.of(context).pop(_AddAction.apps),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;
    switch (action) {
      case _AddAction.files:
        await _pickFiles();
        break;
      case _AddAction.apps:
        await _pickApps();
        break;
    }
  }

  Widget _hotspotPanel(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final resolvedRole = state.resolveHotspotRole();
    final selected = state.settings.hotspotRole;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  resolvedRole == HotspotRole.hosting
                      ? Icons.wifi_tethering
                      : Icons.wifi,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Hotspot role',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final role in HotspotRole.values)
                  ChoiceChip(
                    label: Text(role.label),
                    selected: selected == role,
                    onSelected: (_) async {
                      await state.settings.setHotspotRole(role);
                      await state.refreshDiscovery();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              resolvedRole.hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (resolvedRole == HotspotRole.hosting &&
                state.localIps.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Other devices should look for IPs in your hotspot subnet '
                '(currently ${state.localIps.first}).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _modePanel(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final selected = state.settings.connectivityMode;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transfer mode', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in ConnectivityMode.values)
                  ChoiceChip(
                    label: Text(mode.label),
                    avatar: Icon(_modeIcon(mode), size: 18),
                    selected: selected == mode,
                    onSelected: mode.isAvailable
                        ? (_) => state.settings.setConnectivityMode(mode)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              selected.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stagedFilesPanel(BuildContext context) {
    final theme = Theme.of(context);
    if (_staged.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.upload_file_outlined,
                  color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Tap "Add files" to pick what you want to send, '
                  'then tap a nearby device to start the transfer.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final total = _staged.fold<int>(0, (a, b) => a + b.size);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_staged.length} file${_staged.length == 1 ? "" : "s"} '
                    'staged',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _staged.clear()),
                  child: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_humanBytes(total)} total',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            ..._staged.map((f) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f.fileName,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        _humanBytes(f.size),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _nearbyHeader(BuildContext context, ConnectivityMode mode, int n) {
    final theme = Theme.of(context);
    final canScan = ScanQrPage.isSupported;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            mode == ConnectivityMode.bluetooth
                ? 'Bluetooth sharing'
                : 'Nearby devices',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(width: 8),
          if (n > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$n', style: theme.textTheme.labelSmall),
            ),
          const Spacer(),
          if (mode.usesLanTransport && n > 1)
            IconButton(
              tooltip:
                  _multiSelect ? 'Cancel multi-select' : 'Send to multiple',
              icon: Icon(
                  _multiSelect ? Icons.close : Icons.checklist_rtl_outlined),
              onPressed: _toggleMultiSelect,
            ),
          if (mode.usesLanTransport)
            IconButton(
              tooltip: 'Show pair QR',
              icon: const Icon(Icons.qr_code_2),
              onPressed: () => showPairQrSheet(context),
            ),
          if (mode.usesLanTransport && canScan)
            IconButton(
              tooltip: 'Scan pair QR',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: _scanQr,
            ),
          if (mode.usesLanTransport)
            IconButton(
              tooltip: 'Add device by IP',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _addManualPeer,
            ),
        ],
      ),
    );
  }

  void _toggleMultiSelect() {
    setState(() {
      _multiSelect = !_multiSelect;
      _selectedFingerprints.clear();
    });
  }

  void _toggleSelection(Device peer) {
    setState(() {
      if (_selectedFingerprints.contains(peer.fingerprint)) {
        _selectedFingerprints.remove(peer.fingerprint);
      } else {
        _selectedFingerprints.add(peer.fingerprint);
      }
    });
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(builder: (_) => const ScanQrPage()),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $result')),
      );
    }
  }

  Future<void> _sendStagedToSelected() async {
    if (_staged.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add files first.')),
      );
      return;
    }
    if (_selectedFingerprints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tap one or more devices to send to.')),
      );
      return;
    }
    final state = context.read<AppState>();
    final targets = state.peers.values
        .where((p) => _selectedFingerprints.contains(p.fingerprint))
        .toList();
    final files = _staged.toList();
    setState(() {
      _staged.clear();
      _selectedFingerprints.clear();
      _multiSelect = false;
    });
    await state.sendFilesToMany(peers: targets, files: files);
  }

  Widget _emptyPeers(BuildContext context, ConnectivityMode mode) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.wifi_tethering,
                color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              mode == ConnectivityMode.hotspot
                  ? 'Ready for hotspot sharing'
                  : 'Looking for devices on your Wi-Fi…',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              mode == ConnectivityMode.hotspot
                  ? 'Turn on a phone hotspot, connect the other device to it, then tap + to enter the host address shown in Settings.'
                  : 'Make sure both devices are on the same network. If discovery is blocked, tap the + icon to enter the other device\'s IP manually.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bluetoothPanel(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Bluetooth uses the system share sheet. Pick files or APKs, then tap Share via Bluetooth.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _staged.isEmpty
                  ? null
                  : () => _sendStagedTo(Device(
                        alias: 'Bluetooth device',
                        version: 'bluetooth',
                        deviceModel: 'System Bluetooth',
                        deviceType: 'headless',
                        fingerprint: 'bluetooth',
                        port: 0,
                        protocol: 'http',
                        ip: '0.0.0.0',
                      )),
              icon: const Icon(Icons.bluetooth),
              label: const Text('Share via Bluetooth'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return;
    setState(() {
      for (final f in result.files) {
        if (f.path == null) continue;
        _staged.add(FileInfo(
          id: _uuid.v4(),
          fileName: f.name,
          size: f.size,
          fileType: fileTypeForName(f.name),
          localPath: f.path,
        ));
      }
    });
  }

  Future<void> _pickApps() async {
    if (!AndroidApps.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('APK app sharing is available on Android.')),
      );
      return;
    }
    final apps = await AndroidApps.listLaunchableApps();
    if (!mounted) return;
    if (apps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No shareable installed apps found.')),
      );
      return;
    }
    final selected = <AndroidAppInfo>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Share apps as APKs'),
          content: SizedBox(
            width: 420,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: apps.length,
              itemBuilder: (context, i) {
                final app = apps[i];
                return CheckboxListTile(
                  value: selected.contains(app),
                  onChanged: (checked) => setDialogState(() {
                    if (checked == true) {
                      selected.add(app);
                    } else {
                      selected.remove(app);
                    }
                  }),
                  title: Text(app.label, overflow: TextOverflow.ellipsis),
                  subtitle:
                      Text('${app.packageName} • ${_humanBytes(app.size)}'),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Add APKs'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      for (final app in selected) {
        _staged.add(FileInfo(
          id: _uuid.v4(),
          fileName: '${_safeApkName(app.label)}.apk',
          size: app.size,
          fileType: 'app',
          localPath: app.apkPath,
        ));
      }
    });
  }

  Future<void> _sendStagedTo(Device peer) async {
    if (_staged.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add files first with the "Add files" button.')),
      );
      return;
    }
    final state = context.read<AppState>();
    final files = _staged.toList();
    setState(() => _staged.clear());
    await state.sendFiles(peer: peer, files: files);
  }

  Future<void> _addManualPeer() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add device by IP'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'host or host:port',
            hintText: '192.168.1.42',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final input = controller.text.trim();
    if (input.isEmpty) return;
    final state = context.read<AppState>();
    final probed = await state.probeManualPeer(input);
    if (!mounted) return;
    if (probed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Could not reach $input — is LanLink running on that device?')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${probed.alias} (${probed.ip})')),
      );
    }
  }
}

IconData _modeIcon(ConnectivityMode mode) {
  switch (mode) {
    case ConnectivityMode.lan:
      return Icons.wifi;
    case ConnectivityMode.hotspot:
      return Icons.wifi_tethering;
    case ConnectivityMode.bluetooth:
      return Icons.bluetooth;
  }
}

String _safeApkName(String label) {
  final cleaned = label.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
  return cleaned.isEmpty ? 'app' : cleaned;
}

enum _AddAction { files, apps }

String _humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double size = bytes / 1024.0;
  int i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(1)} ${units[i]}';
}
