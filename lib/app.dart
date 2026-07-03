import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/models/device.dart';
import 'core/models/file_info.dart';
import 'core/settings/app_settings.dart';
import 'core/transfer/receiver.dart';
import 'core/util/format.dart';
import 'state/app_state.dart';
import 'ui/about_page.dart';
import 'ui/help_page.dart';
import 'ui/history_page.dart';
import 'ui/settings_page.dart';
import 'ui/shell/first_run_page.dart';
import 'ui/shell/home_page.dart';
import 'ui/shell/receive_page.dart';
import 'ui/shell/send_page.dart';
import 'ui/v4/v4.dart';

/// The one LanLink app: EmberTheme light+dark (system-follow), a single
/// route table, and a single identity flow (first run = one screen max).
class LanLinkApp extends StatefulWidget {
  const LanLinkApp({super.key, required this.state});

  final AppState state;

  @override
  State<LanLinkApp> createState() => _LanLinkAppState();
}

class _LanLinkAppState extends State<LanLinkApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    widget.state.installIncomingPrompt(_promptForIncoming);
  }

  /// Incoming transfer → v4 ConsentSheet in a bottom sheet. Accept takes
  /// every offered file; anything else (decline, dismiss) rejects.
  Future<AcceptDecision> _promptForIncoming(
      Device peer, List<FileInfo> files) async {
    final nav = _navigatorKey.currentState;
    if (nav == null) return AcceptDecision.reject();
    final state = widget.state;
    // Verification comes from the peer pipeline (pin store); the offer's
    // Device object is what the sender claimed, so re-resolve locally.
    final known = state.peers[peer.fingerprint];
    final verified =
        known?.verified ?? state.settings.isPinned(peer.fingerprint);
    final name = state.settings.nicknameFor(peer.fingerprint) ??
        (peer.alias.trim().isEmpty ? 'Unnamed device' : peer.alias.trim());
    final totalSize = files.fold<int>(0, (sum, f) => sum + f.size);
    // "Always accept from this device" pins trust to the LOCALLY resolved
    // fingerprint (peer pipeline / pin store), never the identity the
    // sender claimed in the offer. No local resolution => no trust option.
    final localFingerprint = known?.fingerprint;
    final canTrust = localFingerprint != null && localFingerprint.isNotEmpty;
    var trustRequested = false;
    final accepted = await showModalBottomSheet<bool>(
      context: nav.context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: VRadius.sheetTop),
      builder: (ctx) => SafeArea(
        child: ConsentSheet(
          data: ConsentRequestData(
            senderName: name,
            fileCount: files.length,
            totalSize: formatBytes(totalSize),
            verified: verified,
            previewFileNames: [for (final f in files) f.fileName],
          ),
          onAccept: () => Navigator.of(ctx).pop(true),
          onDecline: () => Navigator.of(ctx).pop(false),
          onTrustChanged: canTrust ? (v) => trustRequested = v : null,
        ),
      ),
    );
    if (accepted != true) return AcceptDecision.reject();
    if (trustRequested && canTrust) {
      await state.settings.trust(localFingerprint, alias: name);
    }
    return AcceptDecision.accept({for (final f in files) f.id});
  }

  // Built once per process: AppSettings notifies on every write (nickname,
  // trust, save dir, …) and rebuilding MaterialApp with *fresh* ThemeData
  // instances forced a whole-tree theme flush + implicit theme animation
  // each time. Identical instances make those rebuilds cheap.
  static final ThemeData _lightTheme = EmberTheme.light();
  static final ThemeData _darkTheme = EmberTheme.dark();

  static ThemeMode _resolveThemeMode(String raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.state),
        ChangeNotifierProvider.value(value: widget.state.settings),
      ],
      builder: (context, _) {
        // Only the theme mode matters here — selecting it (instead of
        // watching all of AppSettings) stops the 22 unrelated settings
        // notify sites from rebuilding MaterialApp.
        final themeModeRaw =
            context.select<AppSettings, String>((s) => s.themeModeRaw);
        return MaterialApp(
          title: 'LanLink',
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          themeMode: _resolveThemeMode(themeModeRaw),
          theme: _lightTheme,
          darkTheme: _darkTheme,
          home: const _FirstRunGate(),
          routes: {
            '/receive': (_) => const ReceivePage(),
            '/send': (_) => const SendPage(),
            '/settings': (_) => const SettingsPage(),
            '/history': (_) => const HistoryPage(),
            '/about': (_) => const AboutPage(),
            '/help': (_) => const HelpPage(),
          },
        );
      },
    );
  }
}

/// First run = one screen (confirm device name), then home. Returning
/// users (any non-empty onboarded marker) go straight to home.
class _FirstRunGate extends StatefulWidget {
  const _FirstRunGate();

  @override
  State<_FirstRunGate> createState() => _FirstRunGateState();
}

class _FirstRunGateState extends State<_FirstRunGate> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    if (_done) return const HomePage();
    final firstRun =
        context.read<AppSettings>().lastOnboardedVersion.trim().isEmpty;
    if (!firstRun) return const HomePage();
    return FirstRunPage(onDone: () => setState(() => _done = true));
  }
}
