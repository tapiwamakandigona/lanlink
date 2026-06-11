import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../core/settings/app_settings.dart';
import '../core/util/onboarding_gate.dart';
import 'home_page.dart';
import 'onboarding_page.dart';
import 'simple/simple_home_page.dart';

enum _Stage { splash, onboarding, home }

class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  _Stage _stage = _Stage.splash;
  String _currentVersion = '';

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1200), _resolveNextStage);
  }

  Future<void> _resolveNextStage() async {
    if (!mounted) return;
    final settings = context.read<AppSettings>();
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
    } catch (_) {
      _currentVersion = '';
    }
    final showOnboarding = shouldShowOnboarding(
      lastOnboardedVersion: settings.lastOnboardedVersion,
      currentVersion: _currentVersion,
    );
    if (!mounted) return;
    if (showOnboarding) {
      setState(() => _stage = _Stage.onboarding);
      return;
    }
    setState(() => _stage = _Stage.home);
  }

  Future<void> _finishOnboarding() async {
    final settings = context.read<AppSettings>();
    await settings.setLastOnboardedVersion(_currentVersion);
    if (!mounted) return;
    setState(() => _stage = _Stage.home);
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.home:
        // Watching here means flipping the Simple-mode toggle swaps the
        // home screen immediately, without an app restart.
        final simple = context.watch<AppSettings>().simpleMode;
        return simple ? const SimpleHomePage() : const HomePage();
      case _Stage.onboarding:
        return OnboardingPage(onDone: _finishOnboarding);
      case _Stage.splash:
        return _buildSplash(context);
    }
  }

  Widget _buildSplash(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.offline_share_outlined,
                  size: 42,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text('LanLink', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Made by Tapiwa Makandigona',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
