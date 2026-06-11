import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/settings/app_settings.dart';
import 'core/theme/app_theme.dart';
import 'core/transfer/receiver.dart';
import 'state/app_state.dart';
import 'ui/simple/simple_receive_dialog.dart';
import 'ui/splash_gate.dart';
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
        return AcceptDecision.reject();
      }
      // Simple mode swaps the technical prompt for a plain-language one
      // ("Rudo's phone wants to send you 3 photos") with two huge buttons.
      final ({AcceptDecision decision, bool trust}) result;
      if (widget.state.settings.simpleMode) {
        result = await showSimpleReceivePrompt(
          context: nav.context,
          peer: peer,
          files: files,
          nickname: widget.state.settings.nicknameFor(peer.fingerprint),
        );
      } else {
        result = await showReceivePrompt(
          context: nav.context,
          peer: peer,
          files: files,
          canTrust: !widget.state.settings.trustedFingerprints
              .contains(peer.fingerprint),
        );
      }
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
        return ChangeNotifierProvider.value(
          value: widget.state.settings,
          builder: (context, _) {
            final settings = context.watch<AppSettings>();
            final themeMode = AppTheme.resolve(settings.themeModeRaw);
            return MaterialApp(
              title: 'LanLink',
              navigatorKey: _navigatorKey,
              debugShowCheckedModeBanner: false,
              themeMode: themeMode,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              home: const SplashGate(),
            );
          },
        );
      },
    );
  }
}
