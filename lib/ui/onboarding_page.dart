import 'package:flutter/material.dart';

/// First-run / post-update welcome carousel. Every slide is drawn in Flutter
/// (no bundled PNG screenshots) so the tour always matches the real theme and
/// never bloats the download. Reused both as the launch gate and as the
/// "Replay tutorial" target from Settings and the help sheet.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onDone});

  /// Called when the user finishes ("Got it") or taps Skip.
  final VoidCallback onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  static const _slides = <_OnboardingSlide>[
    _OnboardingSlide(
      icon: Icons.offline_share_outlined,
      title: 'Welcome to LanLink',
      body: 'Send files straight between your phones and computers over the '
          'same Wi-Fi or a phone hotspot. No internet, no account, no cloud — '
          'your files never leave the room.',
    ),
    _OnboardingSlide(
      icon: Icons.devices_other,
      title: 'Devices find each other',
      body: 'Open LanLink on both devices and they appear in each other\'s '
          '"Nearby devices" list automatically. On a hotspot, scan the pairing '
          'QR code or tap "Add device by IP" if discovery is blocked.',
    ),
    _OnboardingSlide(
      icon: Icons.upload_file_outlined,
      title: 'Pick, tap, send',
      body: 'Tap "Add" to choose files, then tap the device you want to send '
          'to. The other person gets a prompt to accept — nobody can drop '
          'files on you without your OK.',
    ),
    _OnboardingSlide(
      icon: Icons.verified_user_outlined,
      title: 'Trust your own devices',
      body: 'When a transfer prompt appears, tick "Always accept from this '
          'device" for gear you own so your own phone and laptop send '
          'one-tap next time.',
    ),
    _OnboardingSlide(
      icon: Icons.help_outline,
      title: 'Stuck? Tap the ? button',
      body: 'The "?" button on the home screen opens step-by-step help for '
          'connecting any two devices, plus a quick FAQ. You can replay this '
          'tour anytime from Settings.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _slides.length - 1;

  void _next() {
    if (_isLast) {
      widget.onDone();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onDone,
                child: Text(_isLast ? '' : 'Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _buildSlide(theme, _slides[i]),
              ),
            ),
            _buildDots(theme),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_isLast ? 'Got it' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(ThemeData theme, _OnboardingSlide slide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 56,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              slide.icon,
              size: 56,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            slide.title,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            slide.body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDots(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _slides.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == _index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == _index
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}
