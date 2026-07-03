import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../v4/v4.dart';

/// The entire first-run experience: one lightweight screen that confirms
/// the device name (prefilled with the same platform default the network
/// announcement uses) and drops straight to home.
///
/// Returning users never see this — the gate in app.dart routes them
/// directly to the home screen.
class FirstRunPage extends StatefulWidget {
  const FirstRunPage({super.key, required this.onDone});

  /// Called once the name is confirmed and the first-run marker persisted.
  final VoidCallback onDone;

  @override
  State<FirstRunPage> createState() => _FirstRunPageState();
}

class _FirstRunPageState extends State<FirstRunPage> {
  late final TextEditingController _name;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: context.read<AppState>().displayAlias);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    final state = context.read<AppState>();
    final name = _name.text.trim();
    if (name.isNotEmpty && name != state.settings.alias) {
      await state.settings.setAlias(name);
    }
    String version = 'v4';
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) version = info.version;
    } catch (_) {}
    await state.settings.setLastOnboardedVersion(version);
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(VSpace.x6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.offline_share_outlined,
                        size: 36, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: VSpace.x6),
                  Text('Welcome to LanLink',
                      style: VType.title.copyWith(color: scheme.onSurface),
                      textAlign: TextAlign.center),
                  const SizedBox(height: VSpace.x2),
                  Text(
                    'Send files to nearby devices — no internet, no accounts. '
                    'Other devices will see you by this name:',
                    style:
                        VType.body.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: VSpace.x6),
                  TextField(
                    controller: _name,
                    autofocus: false,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      labelText: 'Device name',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _finish(),
                  ),
                  const SizedBox(height: VSpace.x6),
                  FilledButton(
                    onPressed: _saving ? null : _finish,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('Get started'),
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
