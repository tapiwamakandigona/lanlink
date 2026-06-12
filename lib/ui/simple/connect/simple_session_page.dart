import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/device.dart';
import '../../../core/models/file_info.dart';
import '../../../core/models/session.dart';
import '../../../core/platform/local_hotspot.dart';
import '../../../state/app_state.dart';
import '../../picker/share_picker_page.dart';

/// Simple-mode "you're linked" screen. Both devices land here after the
/// QR scan (or nearby-list tap) and stay here for as many rounds of
/// sending as they like — the link never needs re-pairing.
///
/// Transfers in both directions show up in one list with big progress
/// bars; incoming saves still go through the global accept prompt.
class SimpleSessionPage extends StatefulWidget {
  const SimpleSessionPage({
    super.key,
    required this.peer,
    required this.peerDisplayName,
    this.hotspotHosted = false,
  });

  final Device peer;
  final String peerDisplayName;

  /// True when this device started a hotspot for the link — leaving the
  /// page shuts it down.
  final bool hotspotHosted;

  @override
  State<SimpleSessionPage> createState() => _SimpleSessionPageState();
}

class _SimpleSessionPageState extends State<SimpleSessionPage> {
  static const _uuid = Uuid();
  late final DateTime _connectedAt;

  @override
  void initState() {
    super.initState();
    _connectedAt = DateTime.now();
  }

  @override
  void dispose() {
    if (widget.hotspotHosted) {
      unawaited(LocalHotspot.stop());
    }
    super.dispose();
  }

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  // ----- Sending -----

  Future<void> _sendPicked(List<FileInfo> files) async {
    if (files.isEmpty || !mounted) return;
    final state = context.read<AppState>();
    await state.sendFiles(peer: widget.peer, files: files);
  }

  Future<void> _onSendPhotos() async {
    final picked = await SharePickerPage.open(context);
    if (picked == null || !mounted) return;
    await _sendPicked(picked);
  }

  Future<void> _onSendFiles() async {
    final messenger = ScaffoldMessenger.of(context);
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't open the file chooser on this device."),
        ),
      );
      return;
    }
    if (result == null || !mounted) return;
    final files = [
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
    await _sendPicked(files);
  }

  // ----- Build -----

  List<TransferSession> _linkSessions(AppState state) {
    return [
      for (final s in state.sessions)
        if (s.peer.fingerprint == widget.peer.fingerprint &&
            !s.startedAt.isBefore(_connectedAt))
          s,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = context.watch<AppState>();
    final sessions = _linkSessions(state);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connected'),
        titleTextStyle: theme.textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(theme, scheme),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (_isMobile) ...[
                        Expanded(
                          child: _SendButton(
                            icon: Icons.photo_library_rounded,
                            label: 'Send photos\n& apps',
                            onTap: _onSendPhotos,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: _SendButton(
                          icon: Icons.attach_file_rounded,
                          label: _isMobile ? 'Send\nfiles' : 'Send files',
                          onTap: _onSendFiles,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: sessions.isEmpty
                        ? _buildIdle(theme, scheme)
                        : ListView.separated(
                            itemCount: sessions.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, i) =>
                                _SessionTile(session: sessions[i]),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: Color(0xFF2E7D32),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Connected to ${widget.peerDisplayName}',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdle(ThemeData theme, ColorScheme scheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.swap_vert_rounded, size: 48, color: scheme.onSurfaceVariant),
        const SizedBox(height: 14),
        Text(
          'You can send things both ways —\n'
          'as many rounds as you like.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Icon(icon, size: 34, color: scheme.onPrimary),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One transfer (either direction) with a chunky progress bar and a
/// jargon-free status line.
class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final TransferSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final sending = session.direction == TransferDirection.send;
        final fileCount = session.files.length;
        final what = fileCount == 1
            ? session.files.values.first.file.fileName
            : '$fileCount files';
        final (status, color) = switch (session.status) {
          TransferStatus.completed => (
              sending ? 'Sent!' : 'Saved!',
              const Color(0xFF2E7D32)
            ),
          TransferStatus.failed => ("Didn't finish", scheme.error),
          TransferStatus.cancelled => ('Stopped', scheme.onSurfaceVariant),
          _ => (sending ? 'Sending…' : 'Receiving…', scheme.primary),
        };
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    sending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 20,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      what,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    status,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (session.status == TransferStatus.transferring) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: session.fraction,
                    minHeight: 10,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
