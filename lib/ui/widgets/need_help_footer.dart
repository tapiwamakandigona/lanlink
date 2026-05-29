import 'package:flutter/material.dart';

import '../help_page.dart';

/// Small "Need help?" link rendered at the bottom of every full-page
/// screen except the home (where the "?" button in the AppBar already
/// covers the same ground). Keeping it visually subdued so it doesn't
/// fight the screen's primary content.
class NeedHelpFooter extends StatelessWidget {
  const NeedHelpFooter({super.key, this.padding});

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.help_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () => showHelp(context),
            child: const Text('Need help?'),
          ),
        ],
      ),
    );
  }
}
