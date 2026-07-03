import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/session.dart';
import '../../state/app_state.dart';
import '../shell/saved_location.dart';
import '../shell/session_display.dart';
import '../v4/v4.dart';

/// Hosts one [SessionCard] and subscribes it to its own [TransferSession]
/// for live progress.
///
/// This is the consumer half of the notify-granularity fix: AppState only
/// broadcasts session membership/status changes, so the 10 Hz byte-counter
/// ticks of an active transfer land here — rebuilding exactly this card —
/// instead of fanning out into whole-page rebuilds.
class LiveSessionCard extends StatelessWidget {
  const LiveSessionCard({
    super.key,
    required this.session,
    required this.state,
  });

  /// The live engine session this card renders and listens to.
  final TransferSession session;

  /// App state, for the card's actions (stop/retry/dismiss).
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final card = SessionCard(
          data: sessionCardData(
            session,
            peerName: displayPeerName(state.settings, session.peer),
          ),
          onStop: () => unawaited(state.cancelSession(session)),
          // Only offer "Try again" when a retry can actually do something
          // (outgoing send whose source files still exist on disk).
          onRetry: AppState.canRetry(session)
              ? () => unawaited(state.retrySession(session))
              : null,
          onDismiss: () => state.dismissSession(session),
          onLocate: session.direction == TransferDirection.receive &&
                  session.status == TransferStatus.completed
              ? () => showSavedLocationDialog(context, session)
              : null,
        );
        if (!session.isTerminal) return card;
        // Terminal cards can also be swiped away.
        return Dismissible(
          key: ObjectKey(session),
          onDismissed: (_) => state.dismissSession(session),
          child: card,
        );
      },
    );
  }
}
