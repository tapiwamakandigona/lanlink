import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/session.dart';
import '../core/settings/app_settings.dart';
import '../core/util/format.dart';
import '../state/app_state.dart';
import 'shell/saved_location.dart';
import 'v4/v4.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Single page-level watch; tiles receive what they need as parameters
    // instead of re-subscribing per row inside itemBuilder.
    final state = context.watch<AppState>();
    final settings = state.settings;
    final finished = state.sessions
        .where((s) =>
            s.status == TransferStatus.completed ||
            s.status == TransferStatus.failed ||
            s.status == TransferStatus.cancelled)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (finished.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Clear transfer history?'),
                    content: const Text(
                      'This deletes the saved record of past transfers on this '
                      'device. The actual transferred files are not removed.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await context.read<AppState>().clearHistory();
                }
              },
            ),
        ],
      ),
      body: finished.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No completed transfers yet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: finished.length,
              itemBuilder: (context, i) =>
                  _historyTile(context, settings, finished[i]),
            ),
    );
  }

  Widget _historyTile(
      BuildContext context, AppSettings settings, TransferSession s) {
    final theme = Theme.of(context);
    final isSend = s.direction == TransferDirection.send;
    IconData icon;
    Color color;
    String status;
    switch (s.status) {
      case TransferStatus.completed:
        icon = isSend
            ? Icons.cloud_upload_outlined
            : Icons.cloud_download_outlined;
        // Single-green rule: terminal success uses the semantic palette.
        color = theme.extension<EmberSemantics>()?.success ??
            theme.colorScheme.primary;
        status = isSend ? 'Sent' : 'Received';
        break;
      case TransferStatus.failed:
        icon = Icons.error_outline;
        color = theme.colorScheme.error;
        status = "Didn't go through";
        break;
      case TransferStatus.cancelled:
        icon = Icons.cancel_outlined;
        color = theme.colorScheme.onSurfaceVariant;
        status = 'Stopped';
        break;
      default:
        icon = Icons.sync;
        color = theme.colorScheme.primary;
        status = 'In progress';
    }
    final total = s.files.values.fold<int>(0, (a, b) => a + b.file.size);
    final peerLabel = settings.nicknameFor(s.peer.fingerprint) ??
        (s.peer.alias.isEmpty ? 'Unknown device' : s.peer.alias);
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text('$status • $peerLabel', overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${s.files.length} file${s.files.length == 1 ? "" : "s"} • '
          '${formatBytes(total)} • ${_timeAgo(s.finishedAt ?? s.startedAt)}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: AppState.canRetry(s)
            ? TextButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                onPressed: () => _retry(context, s),
              )
            : s.direction == TransferDirection.receive &&
                    s.status == TransferStatus.completed
                ? TextButton.icon(
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Where is it?'),
                    onPressed: () => showSavedLocationDialog(context, s),
                  )
                : _canSendAgain(s)
                    ? TextButton.icon(
                        icon: const Icon(Icons.send_outlined, size: 18),
                        label: const Text('Send again'),
                        onPressed: () => _retry(context, s),
                      )
                    : null,
        isThreeLine: false,
      ),
    );
  }

  /// A completed outgoing send whose source files still exist can be
  /// re-sent in one tap (ShareIt/Quick Share both offer this; re-picking
  /// the same files is pure friction).
  bool _canSendAgain(TransferSession s) =>
      s.direction == TransferDirection.send &&
      s.status == TransferStatus.completed &&
      s.files.values.any((p) => (p.file.localPath ?? '').isNotEmpty);

  Future<void> _retry(BuildContext context, TransferSession s) async {
    final messenger = ScaffoldMessenger.of(context);
    final state = context.read<AppState>();
    final peerLabel = state.settings.nicknameFor(s.peer.fingerprint) ??
        (s.peer.alias.isEmpty ? 'the device' : s.peer.alias);
    final session = await state.retrySession(s);
    if (session == null) {
      messenger.showSnackBar(
        const SnackBar(
          content:
              Text("Can't retry — the original files are no longer available."),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Retrying transfer to $peerLabel…')),
    );
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
