import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/connectivity/connectivity_mode.dart';
import '../core/util/folder_files.dart';
import '../core/models/device.dart';
import '../core/models/file_info.dart';
import '../core/models/session.dart';
import '../core/platform/android_apps.dart';
import '../state/app_state.dart';
import 'about_page.dart';
import 'history_page.dart';
import 'scan_qr_page.dart';
import 'settings_page.dart';
import '../core/platform/incoming_share.dart';
import 'hotspot/direct_link_page.dart';
import 'pairing/pairing_wizard_page.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _consumePendingShares());
    IncomingShare.onShareReceived(_consumePendingShares);
  }

  Future<void> _consumePendingShares() async {
    if (!mounted) return;
    final shares = await _IncomingShareAdapter.consume();
    if (!mounted || shares.isEmpty) return;
    setState(() => _staged.addAll(shares));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          shares.length == 1
              ? 'Added 1 shared file to send.'
              : 'Added ${shares.length} shared files to send.',
        ),
      ),
    );
  }

  void _openPairingWizard(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PairingWizardPage(
          onDone: () => Navigator.of(context).pop(),
          canSkip: true,
        ),
      ),
    );
  }

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
          PopupMenuButton<_MenuAction>(
            tooltip: 'More options',
            onSelected: (a) => _onMenuAction(context, a),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _MenuAction.help,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.help_outline),
                  title: Text('How to connect'),
                ),
              ),
              PopupMenuItem(
                value: _MenuAction.history,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.history),
                  title: Text('History'),
                ),
              ),
              PopupMenuItem(
                value: _MenuAction.settings,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                ),
              ),
              PopupMenuItem(
                value: _MenuAction.about,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('About'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (state.updateChecker.availableUpdate != null &&
              state.settings.skippedUpdateVersion !=
                  state.updateChecker.availableUpdate!.tagName)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: UpdateAvailableBanner(
                release: state.updateChecker.availableUpdate!,
                onDismiss: () => state.settings.setSkippedUpdateVersion(
                  state.updateChecker.availableUpdate!.tagName,
                ),
              ),
            ),
          _modeStatusBar(context, state),
          if (mode == ConnectivityMode.hotspot) ...[
            const SizedBox(height: 8),
            _hotspotPanel(context, state),
          ],
          if (_staged.isNotEmpty || _isDesktop) ...[
            const SizedBox(height: 16),
            _stagedFilesPanel(context),
          ],
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
              icon: const Icon(Icons.send),
              label: const Text('Send files'),
            ),
    );
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  void _onMenuAction(BuildContext context, _MenuAction action) {
    switch (action) {
      case _MenuAction.help:
        _openPairingWizard(context);
        break;
      case _MenuAction.history:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HistoryPage()),
        );
        break;
      case _MenuAction.settings:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        );
        break;
      case _MenuAction.about:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AboutPage()),
        );
        break;
    }
  }

  Widget _modeStatusBar(BuildContext context, AppState state) {
    final theme = Theme.of(context);
    final mode = state.settings.connectivityMode;
    return Card(
      child: ListTile(
        leading: Icon(_modeIcon(mode), color: theme.colorScheme.primary),
        title: Text(mode.label, style: theme.textTheme.titleSmall),
        subtitle: Text(
          mode.description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: TextButton(
          onPressed: () => _showModeSheet(context, state),
          child: const Text('Change'),
        ),
        onTap: () => _showModeSheet(context, state),
      ),
    );
  }

  Future<void> _showModeSheet(BuildContext context, AppState state) async {
    final selected = state.settings.connectivityMode;
    final chosen = await showModalBottomSheet<ConnectivityMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'How are the devices connected?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            for (final m in ConnectivityMode.values)
              RadioListTile<ConnectivityMode>(
                value: m,
                groupValue: selected,
                onChanged:
                    m.isAvailable ? (v) => Navigator.of(context).pop(v) : null,
                secondary: Icon(_modeIcon(m)),
                title: Text(m.label),
                subtitle: Text(m.description),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (chosen != null) {
      await state.settings.setConnectivityMode(chosen);
    }
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
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Add a whole folder'),
              subtitle: const Text('Sends every file inside, structure kept'),
              onTap: () => Navigator.of(context).pop(_AddAction.folder),
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
      case _AddAction.folder:
        await _pickFolder();
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

  Widget _stagedFilesPanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (_staged.isEmpty) {
      final body = Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.upload_file_outlined,
                  color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isDesktop
                      ? 'Drop files here, or tap "Send files" to pick what you '
                          'want to send. Then tap a nearby device to start.'
                      : 'Tap "Send files" to pick what you want to send, '
                          'then tap a nearby device to start the transfer.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
      return _maybeDroppable(body);
    }
    final total = _staged.fold<int>(0, (a, b) => a + b.size);
    final card = Card(
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
    return _maybeDroppable(card);
  }

  /// Wraps [child] in a [DropTarget] on desktop platforms so users can
  /// drag files from Finder / Explorer / Nautilus onto the staged-files
  /// panel. No-op on mobile platforms — there's no drag source there.
  Widget _maybeDroppable(Widget child) {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return child;
    }
    return DropTarget(
      onDragDone: (detail) {
        final accepted = <FileInfo>[];
        for (final f in detail.files) {
          final p = f.path;
          if (p.isEmpty) continue;
          final file = File(p);
          int size;
          try {
            size = file.lengthSync();
          } catch (_) {
            size = 0;
          }
          accepted.add(FileInfo(
            id: _uuid.v4(),
            fileName: p.split(Platform.pathSeparator).last,
            size: size,
            fileType: fileTypeForName(p),
            localPath: p,
          ));
        }
        if (accepted.isEmpty || !mounted) return;
        setState(() => _staged.addAll(accepted));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accepted.length == 1
                ? 'Added 1 dropped file.'
                : 'Added ${accepted.length} dropped files.'),
          ),
        );
      },
      child: child,
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
            TextButton.icon(
              onPressed: _toggleMultiSelect,
              icon: Icon(
                _multiSelect ? Icons.close : Icons.checklist_outlined,
                size: 18,
              ),
              label: Text(_multiSelect ? 'Cancel' : 'Multi-send'),
            ),
          if (mode.usesLanTransport)
            PopupMenuButton<_AddDeviceAction>(
              tooltip: 'Add a device',
              icon: const Icon(Icons.add),
              onSelected: (a) => _onAddDevice(context, a),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _AddDeviceAction.showQr,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.qr_code_2),
                    title: Text('Show pairing QR'),
                  ),
                ),
                if (canScan)
                  const PopupMenuItem(
                    value: _AddDeviceAction.scanQr,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.qr_code_scanner),
                      title: Text('Scan a QR code'),
                    ),
                  ),
                const PopupMenuItem(
                  value: _AddDeviceAction.enterIp,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.keyboard_outlined),
                    title: Text('Enter IP address'),
                  ),
                ),
                const PopupMenuItem(
                  value: _AddDeviceAction.directLink,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.bolt),
                    title: Text('Direct link (no Wi-Fi)'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _onAddDevice(BuildContext context, _AddDeviceAction action) {
    switch (action) {
      case _AddDeviceAction.showQr:
        showPairQrSheet(context);
        break;
      case _AddDeviceAction.scanQr:
        _scanQr();
        break;
      case _AddDeviceAction.enterIp:
        _addManualPeer();
        break;
      case _AddDeviceAction.directLink:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DirectLinkPage()),
        );
        break;
    }
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
    final picked = await _pickFileInfos();
    if (picked.isEmpty) return;
    setState(() => _staged.addAll(picked));
  }

  /// Stages every file inside a user-picked folder, keeping its structure
  /// (the receiver recreates the subfolders).
  Future<void> _pickFolder() async {
    String? dirPath;
    try {
      dirPath = await FilePicker.platform.getDirectoryPath();
    } catch (_) {
      dirPath = null;
    }
    if (dirPath == null) return;
    final picked = await fileInfosForFolder(dirPath);
    if (!mounted) return;
    if (picked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That folder has no files in it.')),
      );
      return;
    }
    setState(() => _staged.addAll(picked));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added ${picked.length} file${picked.length == 1 ? '' : 's'} '
          'from the folder.',
        ),
      ),
    );
  }

  /// Opens the system file picker and maps the selection to [FileInfo]s.
  /// Returns an empty list if the user cancels.
  Future<List<FileInfo>> _pickFileInfos() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
    } catch (e) {
      // On Linux the picker shells out to zenity/kdialog/qarma; on a system
      // without any of them it throws and previously failed silently. Fall
      // back to a manual path prompt so the user is never stuck.
      if (!mounted) return const [];
      final manual = await _promptManualFilePath(e);
      return manual == null ? const [] : [manual];
    }
    if (result == null) return const [];
    return [
      for (final f in result.files)
        if (f.path != null)
          FileInfo(
            id: _uuid.v4(),
            fileName: f.name,
            size: f.size,
            fileType: fileTypeForName(f.name),
            localPath: f.path,
          ),
    ];
  }

  /// Fallback when the system file picker is unavailable (e.g. no zenity on
  /// Linux): explain the problem and let the user type a file path directly.
  Future<FileInfo?> _promptManualFilePath(Object error) async {
    final controller = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('File picker unavailable'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Platform.isLinux
                  ? 'LanLink could not open the system file dialog. '
                      'Installing zenity usually fixes this '
                      '(e.g. sudo apt install zenity).\n\n'
                      'You can also type the full path of a file to send:'
                  : 'LanLink could not open the system file dialog.\n\n'
                      'You can type the full path of a file to send:',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '/home/you/Videos/movie.mkv',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Add file'),
          ),
        ],
      ),
    );
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File not found: $path')),
        );
      }
      return null;
    }
    return FileInfo(
      id: _uuid.v4(),
      fileName: p.basename(path),
      size: await file.length(),
      fileType: fileTypeForName(p.basename(path)),
      localPath: path,
    );
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
        const SnackBar(content: Text('Tap "Send files" to pick files first.')),
      );
      return;
    }
    final state = context.read<AppState>();
    final files = _staged.toList();
    setState(() => _staged.clear());
    final session = await state.sendFiles(peer: peer, files: files);
    _offerSendAnotherOnComplete(session, peer);
  }

  /// After a send finishes successfully, nudge the user with a "Send another?"
  /// SnackBar that re-opens the file picker for the same peer. Bluetooth
  /// sessions are skipped — they hand off to the system share sheet, which
  /// has its own follow-up flow.
  void _offerSendAnotherOnComplete(TransferSession session, Device peer) {
    if (peer.fingerprint == 'bluetooth') return;
    void listener() {
      if (session.status != TransferStatus.completed) return;
      session.removeListener(listener);
      if (!mounted) return;
      final peerName =
          context.read<AppState>().settings.nicknameFor(peer.fingerprint) ??
              (peer.alias.isEmpty ? 'device' : peer.alias);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sent to $peerName.'),
          action: SnackBarAction(
            label: 'Send another',
            onPressed: () => _sendAnotherTo(peer),
          ),
        ),
      );
    }

    session.addListener(listener);
  }

  Future<void> _sendAnotherTo(Device peer) async {
    final state = context.read<AppState>();
    final picked = await _pickFileInfos();
    if (picked.isEmpty || !mounted) return;
    final session = await state.sendFiles(peer: peer, files: picked);
    _offerSendAnotherOnComplete(session, peer);
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

enum _AddAction { files, apps, folder }

enum _MenuAction { help, history, settings, about }

enum _AddDeviceAction { showQr, scanQr, enterIp, directLink }

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

/// Local alias so the [HomePage] state class doesn't need to depend on
/// the platform-channel name. Lets us swap the implementation out in
/// unit tests later.
class _IncomingShareAdapter {
  static Future<List<FileInfo>> consume() => IncomingShare.consume();
}
