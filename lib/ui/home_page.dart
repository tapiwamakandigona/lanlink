import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../core/models/device.dart';
import '../core/models/file_info.dart';
import '../state/app_state.dart';
import 'history_page.dart';
import 'settings_page.dart';
import 'widgets/device_card.dart';
import 'widgets/progress_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<FileInfo> _staged = [];
  final _uuid = const Uuid();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
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
                _stagedFilesPanel(context),
                const SizedBox(height: 16),
                _nearbyHeader(context, peers.length),
                if (peers.isEmpty)
                  _emptyPeers(context)
                else
                  ...peers.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DeviceCard(
                        device: p,
                        onTap: () => _sendStagedTo(p),
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
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickFiles,
        icon: const Icon(Icons.add),
        label: const Text('Add files'),
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

  Widget _nearbyHeader(BuildContext context, int n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('Nearby devices', style: theme.textTheme.titleMedium),
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
          IconButton(
            tooltip: 'Add device by IP',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _addManualPeer,
          ),
        ],
      ),
    );
  }

  Widget _emptyPeers(BuildContext context) {
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
              'Looking for devices on your Wi-Fi…',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Make sure both devices are on the same network. '
              'If discovery is blocked, tap the + icon to enter the other '
              'device\'s IP manually.',
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
