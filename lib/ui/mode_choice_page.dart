import 'package:flutter/material.dart';

/// First-run setup step shown right after the welcome carousel: lets the
/// user pick between Simple mode (two giant buttons) and the full app.
/// The choice is never final — both modes link back to each other and the
/// toggle lives in Settings.
class ModeChoicePage extends StatelessWidget {
  const ModeChoicePage({super.key, required this.onChosen});

  /// Called with `true` when the user picks Simple mode, `false` for full.
  final ValueChanged<bool> onChosen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    'How do you want to use LanLink?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You can switch any time in Settings.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _ModeCard(
                      icon: Icons.touch_app_outlined,
                      title: 'Simple',
                      body: 'Two big buttons: Send and Receive. '
                          'Great for family members who just want it to work.',
                      filled: true,
                      onTap: () => onChosen(true),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _ModeCard(
                      icon: Icons.tune,
                      title: 'Full',
                      body: 'Device list, folders, QR pairing, history and '
                          'every setting. For people who like the controls.',
                      filled: false,
                      onTap: () => onChosen(false),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
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
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: filled ? null : Border.all(color: scheme.primary, width: 3),
          ),
          // FittedBox keeps the card overflow-proof on short/landscape
          // screens: the content scales down instead of clipping.
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 44, color: fg),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(color: fg, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: sub),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
