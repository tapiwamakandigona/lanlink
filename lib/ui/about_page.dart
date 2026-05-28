import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widgets/check_for_updates_tile.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static final Uri _website = Uri.parse('https://tapiwa.me');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About LanLink')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.offline_share_outlined,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('LanLink', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Fast local file sharing for Windows and Android.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Made by Tapiwa Makandigona',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const CheckForUpdatesTile(),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Visit tapiwa.me'),
              subtitle: Text(_website.toString()),
              trailing: const Icon(Icons.open_in_new),
              onTap: () =>
                  launchUrl(_website, mode: LaunchMode.externalApplication),
            ),
          ),
        ],
      ),
    );
  }
}
