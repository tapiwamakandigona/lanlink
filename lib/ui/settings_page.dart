import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'widgets/check_for_updates_tile.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _aliasCtrl;
  late final TextEditingController _saveDirCtrl;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _aliasCtrl = TextEditingController(text: state.settings.alias);
    _saveDirCtrl = TextEditingController(text: state.settings.saveDir ?? '');
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _saveDirCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('This device', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _aliasCtrl,
            decoration: const InputDecoration(
              labelText: 'Device name (shown to peers)',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => state.settings.setAlias(v),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => state.settings.setAlias(_aliasCtrl.text),
              child: const Text('Save device name'),
            ),
          ),
          const Divider(height: 32),
          Text('Save folder', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            Platform.isAndroid
                ? 'Incoming files are saved to your phone\'s Downloads/LanLink folder so you can find them in the Files app right away.'
                : 'Where incoming files are saved.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (Platform.isAndroid)
            InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Download/LanLink',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            )
          else
            TextField(
              controller: _saveDirCtrl,
              readOnly: true,
              decoration: InputDecoration(
                hintText: '(default location)',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Reset to default',
                      icon: const Icon(Icons.refresh),
                      onPressed: () async {
                        await state.settings.setSaveDir(null);
                        _saveDirCtrl.text = '';
                      },
                    ),
                    IconButton(
                      tooltip: 'Choose folder',
                      icon: const Icon(Icons.folder_open),
                      onPressed: _pickFolder,
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: state.settings.quickSave,
            onChanged: (v) => state.settings.setQuickSave(v),
            title: const Text('Quick Save from trusted devices'),
            subtitle: const Text(
              'Auto-accept files from devices you previously checked "trust" on.',
            ),
          ),
          const Divider(height: 32),
          Text('Network', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _kv(
              context,
              'Listening on',
              '${state.localIps.isEmpty ? "no LAN interface" : state.localIps.join(", ")}'
                  ' : ${state.port ?? "?"}'),
          _kv(context, 'Fingerprint',
              state.fingerprint.isEmpty ? '(generating…)' : state.fingerprint),
          const SizedBox(height: 8),
          if (state.localIps.isNotEmpty)
            FilledButton.tonalIcon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final addr = '${state.localIps.first}:${state.port}';
                await Clipboard.setData(ClipboardData(text: addr));
                messenger.showSnackBar(
                  SnackBar(content: Text('Copied $addr')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy address'),
            ),
          const Divider(height: 32),
          Text('Updates', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'LanLink checks GitHub for new releases. Updates are always optional and never installed automatically.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          const CheckForUpdatesTile(),
          const Divider(height: 32),
          Text('Trusted devices', style: theme.textTheme.titleMedium),
          if (state.settings.trustedFingerprints.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'None yet. Tick "Auto-accept from this device" when a transfer prompt appears.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ...state.settings.trustedFingerprints.map((fp) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(fp, style: theme.textTheme.bodySmall),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => state.settings.untrust(fp),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(k,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ),
          Expanded(
            child: SelectableText(v, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFolder() async {
    final state = context.read<AppState>();
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    // Validate we can actually write to it on desktop platforms.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
    await state.settings.setSaveDir(path);
    if (!mounted) return;
    _saveDirCtrl.text = path;
  }
}
