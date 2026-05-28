import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static final Uri _website = Uri.parse('https://tapiwa.me');
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(
            () => _version = 'Version ${info.version} (${info.buildNumber})');
      }
    } catch (_) {
      // Ignore — version label is decorative.
    }
  }

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
                    'Fast local file sharing for Windows, macOS, Android and iOS.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (_version.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _version,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
