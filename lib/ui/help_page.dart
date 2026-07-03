import 'dart:io';

import 'package:flutter/material.dart';

import '../core/models/session.dart';
import '../core/util/pairing_guide.dart';

/// Help + "Get connected" guide reachable from the home-screen "?" button.
/// Walks the user through direction → other-device → tailored steps, lists a
/// short FAQ, and offers a tutorial replay.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  TransferDirection? _direction;
  OtherDeviceKind? _other;

  SelfPlatform get _self {
    if (Platform.isAndroid) return SelfPlatform.android;
    if (Platform.isIOS) return SelfPlatform.ios;
    if (Platform.isWindows) return SelfPlatform.windows;
    if (Platform.isMacOS) return SelfPlatform.macos;
    if (Platform.isLinux) return SelfPlatform.linux;
    return SelfPlatform.other;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Help & getting connected')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Get connected', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Answer two quick questions and we\'ll show you exactly how to '
            'link this device with the other one.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _questionCard(
            theme,
            'What do you want to do?',
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Send files'),
                  avatar: const Icon(Icons.upload, size: 18),
                  selected: _direction == TransferDirection.send,
                  onSelected: (_) =>
                      setState(() => _direction = TransferDirection.send),
                ),
                ChoiceChip(
                  label: const Text('Receive files'),
                  avatar: const Icon(Icons.download, size: 18),
                  selected: _direction == TransferDirection.receive,
                  onSelected: (_) =>
                      setState(() => _direction = TransferDirection.receive),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _questionCard(
            theme,
            'What is the other device?',
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in OtherDeviceKind.values)
                  ChoiceChip(
                    label: Text(kind.label),
                    selected: _other == kind,
                    onSelected: (_) => setState(() => _other = kind),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_direction != null && _other != null)
            _guideCard(theme)
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Pick an option above to see step-by-step instructions.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          const Divider(height: 40),
          Text('Frequently asked', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          ..._faq.map(
            (qa) => Card(
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                title: Text(qa.$1, style: theme.textTheme.titleSmall),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(qa.$2, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _questionCard(ThemeData theme, String title, Widget child) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _guideCard(ThemeData theme) {
    final guide = resolvePairingGuide(
      self: _self,
      direction: _direction!,
      other: _other!,
    );
    return Card(
      color: theme.colorScheme.primaryContainer.withOpacity(0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(guide.title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < guide.steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: theme.colorScheme.primary,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        guide.steps[i],
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            if (guide.tip != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      guide.tip!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const List<(String, String)> _faq = [
    (
      'Do I need an internet connection?',
      'No. LanLink only uses your local Wi-Fi or a phone hotspot. Nothing is '
          'uploaded to the internet and there is no account to sign in to.',
    ),
    (
      'Why don\'t I see the other device?',
      'Make sure both devices are on the same Wi-Fi or hotspot and that '
          'LanLink is open on both. Some networks block automatic discovery — '
          'in that case use the Scan QR / Show QR buttons, or "Add device by '
          'IP" with the address shown in Settings.',
    ),
    (
      'Where do received files go?',
      'On Android they land in Downloads/LanLink so you can open them from '
          'the Files app right away. On computers you can pick the save folder '
          'in Settings.',
    ),
    (
      'Is it safe? Can strangers send me files?',
      'Every incoming transfer asks you to accept or decline first, so nobody '
          'can drop files on you without your OK. You can mark your own '
          'devices as trusted for one-tap accept.',
    ),
    (
      'A transfer failed. What do I do?',
      'Open History and tap Retry on the failed transfer. If it keeps '
          'failing, move the devices closer together and make sure both stay '
          'on the same network.',
    ),
  ];
}

/// Convenience launcher used by the home-screen "?" button.
Future<void> showHelp(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const HelpPage()),
  );
}
