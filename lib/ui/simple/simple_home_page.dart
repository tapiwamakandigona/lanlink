import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/file_info.dart';
import '../../core/models/session.dart';
import '../../core/settings/app_settings.dart';
import '../../state/app_state.dart';
import 'simple_saved_page.dart';
import 'simple_send_flow.dart';

/// Simple-mode home screen: the entire screen is two giant buttons —
/// Send and Receive — plus a reassuring status line. Designed for
/// non-technical users; all transport details are hidden.
class SimpleHomePage extends StatefulWidget {
  const SimpleHomePage({super.key});

  @override
  State<SimpleHomePage> createState() => _SimpleHomePageState();
}

class _SimpleHomePageState extends State<SimpleHomePage> {
  static const _uuid = Uuid();

  late final AppState _state;
  late final DateTime _mountedAt;

  /// Receive sessions we've already shown the "All saved!" page for.
  final Set<TransferSession> _celebrated = {};
  bool _savedPageOpen = false;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _mountedAt = DateTime.now();
    _state.addListener(_maybeCelebrateReceive);
  }

  @override
  void dispose() {
    _state.removeListener(_maybeCelebrateReceive);
    super.dispose();
  }

  /// Watches for incoming transfers that just completed and pushes the
  /// full-screen "All saved!" confirmation — the success feedback the
  /// full UI only shows as a small chip.
  void _maybeCelebrateReceive() {
    if (!mounted || _savedPageOpen) return;
    for (final session in _state.sessions) {
      if (session.direction != TransferDirection.receive) continue;
      if (session.status != TransferStatus.completed) continue;
      final finished = session.finishedAt;
      if (finished == null || finished.isBefore(_mountedAt)) continue;
      if (_celebrated.contains(session)) continue;
      _celebrated.add(session);
      _savedPageOpen = true;
      final nickname = _state.settings.nicknameFor(session.peer.fingerprint);
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => SimpleSavedPage(
                session: session,
                peerDisplayName: nickname,
              ),
            ),
          )
          .whenComplete(() => _savedPageOpen = false);
      return;
    }
  }

  String get _deviceName {
    final alias = _state.settings.alias.trim();
    if (alias.isNotEmpty) return alias;
    if (Platform.isAndroid) return 'Android device';
    if (Platform.isIOS) return 'iOS device';
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'this device';
    }
  }

  Future<void> _onSendTap() async {
    final navigator = Navigator.of(context);
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
    if (result == null) return;
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
    if (files.isEmpty || !mounted) return;
    unawaited(navigator.push(
      MaterialPageRoute(
        builder: (_) => SimpleDevicePickerPage(files: files),
      ),
    ));
  }

  /// Desktop only: files dragged onto the Send button skip the picker and
  /// go straight to "who should get these?".
  void _onFilesDropped(DropDoneDetails detail) {
    final files = <FileInfo>[];
    for (final f in detail.files) {
      final path = f.path;
      if (path.isEmpty) continue;
      int size;
      try {
        size = File(path).lengthSync();
      } catch (_) {
        size = 0;
      }
      files.add(FileInfo(
        id: _uuid.v4(),
        fileName: path.split(Platform.pathSeparator).last,
        size: size,
        fileType: fileTypeForName(path),
        localPath: path,
      ));
    }
    if (files.isEmpty || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SimpleDevicePickerPage(files: files),
      ),
    );
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  void _onReceiveTap() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ReceiveReadyPage(deviceName: _deviceName),
      ),
    );
  }

  Future<void> _onExitSimpleMode() async {
    final settings = context.read<AppSettings>();
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch to the full app?'),
        content: const Text(
          'The full version shows every option and setting. '
          'You can come back to Simple mode any time from Settings.',
        ),
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay here'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await settings.setSimpleMode(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = context.watch<AppSettings>();
    // Rebuild the status line when the alias changes.
    context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'LanLink',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      // Long-press is the caregiver escape hatch when the
                      // visible "Full version" button is disabled in
                      // Settings.
                      GestureDetector(
                        onLongPress: _onExitSimpleMode,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Simple mode',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Builder(builder: (context) {
                      final button = _BigActionButton(
                        icon: Icons.upload_rounded,
                        label: 'Send',
                        sublabel: _isDesktop
                            ? 'Drop files here — or click to choose'
                            : 'Share photos & files',
                        filled: true,
                        onTap: _onSendTap,
                      );
                      if (!_isDesktop) return button;
                      return DropTarget(
                        onDragDone: _onFilesDropped,
                        child: button,
                      );
                    }),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _BigActionButton(
                      icon: Icons.download_rounded,
                      label: 'Receive',
                      sublabel: 'Get files from family',
                      filled: false,
                      onTap: _onReceiveTap,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.circle,
                          size: 10, color: Color(0xFF2C9A4B)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Ready — visible as “$_deviceName”',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: const Color(0xFF2C9A4B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (settings.simpleModeExitButton) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _onExitSimpleMode,
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.onSurfaceVariant,
                      ),
                      child: const Text('Full version'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BigActionButton extends StatelessWidget {
  const _BigActionButton({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = filled ? scheme.primary : scheme.surfaceContainerLowest;
    final fg = filled ? scheme.onPrimary : scheme.onSurface;
    final sub =
        filled ? scheme.onPrimary.withOpacity(0.85) : scheme.onSurfaceVariant;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: filled ? null : Border.all(color: scheme.primary, width: 3),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: fg),
              const SizedBox(height: 10),
              Text(
                label,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(color: fg, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                sublabel,
                style: theme.textTheme.titleMedium?.copyWith(color: sub),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen "ready to receive" helper. Receiving is always on in the
/// background; this page exists to give a nervous user something concrete
/// to do ("hand the phone over / wait") and to confirm the device is
/// discoverable. The incoming prompt itself appears globally.
class _ReceiveReadyPage extends StatelessWidget {
  const _ReceiveReadyPage({required this.deviceName});

  final String deviceName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 56,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(
                        Icons.wifi_tethering,
                        size: 56,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Ready to receive',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'On the other device, tap Send\n'
                    'and choose “$deviceName”.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "We'll ask you before anything is saved.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
