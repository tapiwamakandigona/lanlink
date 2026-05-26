import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/transfer/receiver.dart';
import 'state/app_state.dart';
import 'ui/home_page.dart';
import 'ui/widgets/receive_dialog.dart';

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
    widget.state.installIncomingPrompt((peer, files) async {
      final nav = _navigatorKey.currentState;
      if (nav == null) {
        // UI not ready yet — reject so sender can retry.
        return AcceptDecision.reject();
      }
      final result = await showReceivePrompt(
        context: nav.context,
        peer: peer,
        files: files,
        canTrust: !widget.state.settings.trustedFingerprints
            .contains(peer.fingerprint),
      );
      if (result.trust) {
        await widget.state.settings.trust(peer.fingerprint);
      }
      return result.decision;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.state,
      builder: (context, _) {
        // Also expose settings so widgets that only need settings can listen
        // to it directly without depending on AppState.
        return ChangeNotifierProvider.value(
          value: widget.state.settings,
          child: MaterialApp(
            title: 'LanLink',
            navigatorKey: _navigatorKey,
            debugShowCheckedModeBanner: false,
            themeMode: ThemeMode.system,
            theme: _buildLight(),
            darkTheme: _buildDark(),
            home: const HomePage(),
          ),
        );
      },
    );
  }
}

ThemeData _buildLight() {
  final base = ColorScheme.fromSeed(seedColor: const Color(0xFF3D7BFF));
  return ThemeData(
    colorScheme: base,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: base.surface,
      foregroundColor: base.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
  );
}

ThemeData _buildDark() {
  final base = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3D7BFF),
    brightness: Brightness.dark,
  );
  return ThemeData(
    colorScheme: base,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: base.surface,
      foregroundColor: base.onSurface,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardTheme(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
  );
}
