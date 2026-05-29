import 'dart:async';

import 'package:flutter/material.dart';

/// Subtle "Need a hand?" banner that fades in after the user has sat on
/// the home screen for [idle] without staging files or tapping a peer.
/// Tapping the banner opens whatever helper the host provides via
/// [onTap]. The banner stays dismissed for the lifetime of the widget
/// once the user closes it.
class IdleNudge extends StatefulWidget {
  const IdleNudge({
    super.key,
    required this.idle,
    required this.onTap,
    this.message = "Stuck? We can walk you through connecting another device.",
    this.actionLabel = 'Show me',
  });

  final Duration idle;
  final VoidCallback onTap;
  final String message;
  final String actionLabel;

  @override
  State<IdleNudge> createState() => _IdleNudgeState();
}

class _IdleNudgeState extends State<IdleNudge> {
  Timer? _timer;
  bool _show = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  void _arm() {
    _timer?.cancel();
    _timer = Timer(widget.idle, () {
      if (!mounted || _dismissed) return;
      setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: !_show
          ? const SizedBox.shrink()
          : Padding(
              key: const ValueKey('idle-nudge-visible'),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    widget.onTap();
                    setState(() => _dismissed = true);
                    setState(() => _show = false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.message,
                            style: TextStyle(
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            widget.onTap();
                            setState(() => _dismissed = true);
                            setState(() => _show = false);
                          },
                          child: Text(widget.actionLabel),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Dismiss',
                          color: theme.colorScheme.onTertiaryContainer,
                          onPressed: () {
                            setState(() {
                              _dismissed = true;
                              _show = false;
                            });
                          },
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
