import 'package:flutter/material.dart';

import '../../core/models/device.dart';
import '../../core/models/file_info.dart';
import '../../core/transfer/receiver.dart';
import '../../core/util/format.dart';

/// Modal prompt shown to the user when a peer wants to send files.
///
/// Returns an [AcceptDecision]. If the user dismisses the dialog without
/// pressing a button, we treat it as a rejection.
class ReceivePromptDialog extends StatefulWidget {
  const ReceivePromptDialog({
    super.key,
    required this.peer,
    required this.files,
    required this.canTrust,
  });

  final Device peer;
  final List<FileInfo> files;
  final bool canTrust;

  @override
  State<ReceivePromptDialog> createState() => _ReceivePromptDialogState();
}

class _ReceivePromptDialogState extends State<ReceivePromptDialog> {
  bool _trustForever = false;

  int get _totalBytes => widget.files.fold<int>(0, (a, b) => a + b.size);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title:
          Text('${widget.peer.alias} wants to send you ${widget.files.length} '
              'file${widget.files.length == 1 ? "" : "s"}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360, maxWidth: 380),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.peer.ip}:${widget.peer.port}'
              '${widget.peer.deviceModel.isNotEmpty ? " • ${widget.peer.deviceModel}" : ""}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.files.length,
                itemBuilder: (context, i) {
                  final f = widget.files[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(f.fileName, overflow: TextOverflow.ellipsis),
                    subtitle: Text(formatBytes(f.size)),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Total: ${formatBytes(_totalBytes)}',
              style: theme.textTheme.bodyMedium,
            ),
            if (widget.canTrust)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _trustForever,
                onChanged: (v) => setState(() => _trustForever = v ?? false),
                title: const Text('Auto-accept from this device in the future'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_RejectResult()),
          child: const Text('Decline'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_AcceptResult(_trustForever)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _AcceptResult {
  _AcceptResult(this.trustForever);
  final bool trustForever;
}

class _RejectResult {}

/// Public helper that shows the dialog and folds the result back to an
/// [AcceptDecision] (plus an out-param indicating whether the user wanted
/// to trust the sender permanently).
Future<({AcceptDecision decision, bool trust})> showReceivePrompt({
  required BuildContext context,
  required Device peer,
  required List<FileInfo> files,
  required bool canTrust,
}) async {
  final result = await showDialog<Object?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ReceivePromptDialog(
      peer: peer,
      files: files,
      canTrust: canTrust,
    ),
  );
  if (result is _AcceptResult) {
    return (
      decision: AcceptDecision.accept(files.map((f) => f.id).toSet()),
      trust: result.trustForever,
    );
  }
  return (decision: AcceptDecision.reject(), trust: false);
}
