import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/device.dart';
import '../../state/app_state.dart';
import '../peer_history_page.dart';

/// Long-press / overflow menu for a discovered peer. Lets the user assign
/// a persistent nickname, jump to a per-peer history view, and toggle the
/// peer's "trusted" status so future transfers can quick-save.
Future<void> showPeerActionSheet(BuildContext context, Device peer) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _PeerActionSheet(peer: peer),
  );
}

class _PeerActionSheet extends StatelessWidget {
  const _PeerActionSheet({required this.peer});

  final Device peer;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.settings;
    final theme = Theme.of(context);
    final nickname = settings.nicknameFor(peer.fingerprint);
    final isTrusted = settings.trustedFingerprints.contains(peer.fingerprint);
    final displayName =
        nickname ?? (peer.alias.isEmpty ? 'Unknown device' : peer.alias);
    final canTrust = peer.fingerprint.isNotEmpty;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                  child: Icon(
                    Icons.devices,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: theme.textTheme.titleMedium),
                      if (nickname != null && peer.alias.isNotEmpty)
                        Text(
                          'aka ${peer.alias}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      Text(
                        '${peer.ip}:${peer.port}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(nickname == null ? 'Set nickname' : 'Edit nickname'),
            subtitle: nickname == null
                ? const Text('Pin a friendly name like "My Laptop"')
                : Text('Currently: $nickname'),
            onTap: () async {
              Navigator.of(context).pop();
              await _renameDialog(context, peer);
            },
          ),
          if (nickname != null)
            ListTile(
              leading: const Icon(Icons.label_off_outlined),
              title: const Text('Clear nickname'),
              onTap: () async {
                await settings.setNickname(peer.fingerprint, null);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('View history with this device'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PeerHistoryPage(peer: peer),
              ));
            },
          ),
          if (canTrust)
            SwitchListTile(
              secondary: Icon(
                isTrusted ? Icons.verified_user : Icons.verified_user_outlined,
              ),
              title: const Text('Trusted device'),
              subtitle: const Text(
                'Skip the accept prompt when Quick Save is on.',
              ),
              value: isTrusted,
              onChanged: (v) async {
                if (v) {
                  await settings.trust(peer.fingerprint);
                } else {
                  await settings.untrust(peer.fingerprint);
                }
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _renameDialog(BuildContext context, Device peer) async {
    final state = context.read<AppState>();
    final controller = TextEditingController(
      text: state.settings.nicknameFor(peer.fingerprint) ?? '',
    );
    final newName = await showDialog<String?>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Nickname'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Show as',
            hintText: peer.alias.isEmpty ? 'My Laptop' : peer.alias,
            border: const OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogCtx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null) return;
    await state.settings.setNickname(
      peer.fingerprint,
      newName.isEmpty ? null : newName,
    );
  }
}
