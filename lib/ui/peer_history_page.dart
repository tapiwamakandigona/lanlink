import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/device.dart';
import '../core/models/session.dart';
import '../core/util/format.dart';
import '../state/app_state.dart';

/// History list filtered to a single peer fingerprint. Shows the same
/// completed / failed / cancelled sessions as [HistoryPage] but only those
/// whose peer matches the given fingerprint — useful for "what did I send
/// to my laptop last week".
class PeerHistoryPage extends StatelessWidget {
  const PeerHistoryPage({super.key, required this.peer});

  final Device peer;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final nickname = state.settings.nicknameFor(peer.fingerprint);
    final title =
        nickname ?? (peer.alias.isEmpty ? 'Unknown device' : peer.alias);
    final all = state.sessions
        .where((s) =>
            s.peer.fingerprint == peer.fingerprint &&
            (s.status == TransferStatus.completed ||
                s.status == TransferStatus.failed ||
                s.status == TransferStatus.cancelled))
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text('History • $title')),
      body: all.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No transfers with $title yet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: all.length,
              itemBuilder: (context, i) => _historyTile(context, all[i]),
            ),
    );
  }

  Widget _historyTile(BuildContext context, TransferSession s) {
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
        color = Colors.green;
        status = 'Completed';
        break;
      case TransferStatus.failed:
        icon = Icons.error_outline;
        color = theme.colorScheme.error;
        status = 'Failed';
        break;
      case TransferStatus.cancelled:
        icon = Icons.cancel_outlined;
        color = theme.colorScheme.onSurfaceVariant;
        status = 'Cancelled';
        break;
      default:
        icon = Icons.sync;
        color = theme.colorScheme.primary;
        status = 'In progress';
    }
    final total = s.files.values.fold<int>(0, (a, b) => a + b.file.size);
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          '$status • ${isSend ? "Sent" : "Received"}',
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${s.files.length} file${s.files.length == 1 ? "" : "s"} • '
          '${formatBytes(total)} • ${_timeAgo(s.finishedAt ?? s.startedAt)}',
          style: theme.textTheme.bodySmall,
        ),
      ),
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
