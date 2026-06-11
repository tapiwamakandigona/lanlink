import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../hotspot/direct_link_page.dart';

import '../../core/connectivity/connectivity_mode.dart';
import '../../core/models/session.dart';
import '../../core/onboarding/pairing_choice.dart';
import '../../core/platform/system_settings.dart';
import '../../core/util/pairing_guide.dart';
import '../../state/app_state.dart';
import '../scan_qr_page.dart';
import '../widgets/pair_qr_sheet.dart';

/// Launch-time pairing wizard. Three steps:
///   1. Direction (Send / Receive).
///   2. What the other device is.
///   3. Tailored, tap-through instructions.
///
/// Every choice the user has already made survives a back-press, and
/// the final step calls [onDone] when they tap "I'm connected" so the
/// shell can drop into the regular home screen.
class PairingWizardPage extends StatefulWidget {
  const PairingWizardPage({
    super.key,
    required this.onDone,
    this.canSkip = true,
    this.initial,
  });

  /// Fires when the user finishes the wizard or chooses to skip.
  final VoidCallback onDone;

  /// Whether to show the "Skip for now" link on Step 1. Disabled when
  /// the wizard is replayed from Settings — there we keep a back arrow
  /// instead.
  final bool canSkip;

  /// Optional pre-filled choice. When the user picks "Same as last
  /// time" we open the wizard with [initial] set and jump straight to
  /// the tailored instructions.
  final PairingChoice? initial;

  @override
  State<PairingWizardPage> createState() => _PairingWizardPageState();
}

class _PairingWizardPageState extends State<PairingWizardPage> {
  late final PageController _pages =
      PageController(initialPage: widget.initial != null ? 2 : 0);
  int _index = 0;
  TransferDirection? _direction;
  OtherDeviceKind? _other;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _direction = widget.initial!.direction;
      _other = widget.initial!.other;
      _index = 2;
    }
  }

  SelfPlatform get _self {
    if (Platform.isAndroid) return SelfPlatform.android;
    if (Platform.isIOS) return SelfPlatform.ios;
    if (Platform.isWindows) return SelfPlatform.windows;
    if (Platform.isMacOS) return SelfPlatform.macos;
    if (Platform.isLinux) return SelfPlatform.linux;
    return SelfPlatform.other;
  }

  Future<void> _goTo(int page) async {
    setState(() => _index = page);
    await _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  void _onPickDirection(TransferDirection dir) {
    setState(() => _direction = dir);
    _goTo(1);
  }

  void _onPickOther(OtherDeviceKind other) {
    setState(() => _other = other);
    _goTo(2);
  }

  Future<void> _finish() async {
    if (_direction != null && _other != null) {
      final settings = context.read<AppState>().settings;
      await settings.setLastPairing(
        PairingChoice(direction: _direction!, other: _other!),
      );
    }
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Get connected'),
        leading: _index > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => _goTo(_index - 1),
              )
            : null,
        actions: [
          if (widget.canSkip && _index == 0)
            TextButton(
              onPressed: widget.onDone,
              child: const Text("I'll set it up later"),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _StepIndicator(active: _index, total: 3),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _DirectionStep(
                    onPick: _onPickDirection,
                    lastPairing: context.watch<AppState>().settings.lastPairing,
                    onUseLastPairing: _onUseLastPairing,
                    selected: _direction,
                  ),
                  _OtherDeviceStep(
                    onPick: _onPickOther,
                    selected: _other,
                  ),
                  if (_direction != null && _other != null)
                    _InstructionsStep(
                      self: _self,
                      direction: _direction!,
                      other: _other!,
                      onDone: _finish,
                    )
                  else
                    Center(
                      child: Text(
                        'Pick a direction and a device first.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onUseLastPairing(PairingChoice choice) {
    setState(() {
      _direction = choice.direction;
      _other = choice.other;
    });
    _goTo(2);
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.active, required this.total});
  final int active;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: List.generate(total, (i) {
        final reached = i <= active;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 4,
            decoration: BoxDecoration(
              color: reached
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

class _DirectionStep extends StatelessWidget {
  const _DirectionStep({
    required this.onPick,
    required this.lastPairing,
    required this.onUseLastPairing,
    required this.selected,
  });
  final ValueChanged<TransferDirection> onPick;
  final PairingChoice? lastPairing;
  final ValueChanged<PairingChoice> onUseLastPairing;
  final TransferDirection? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('What do you want to do?', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          "Answer two quick questions and we'll show you exactly what to "
          'tap on this device to get connected.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        if (lastPairing != null) ...[
          Card(
            color: theme.colorScheme.primaryContainer,
            child: ListTile(
              leading: Icon(
                Icons.history,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              title: Text(
                'Same as last time?',
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                lastPairing!.summary,
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              trailing: Icon(
                Icons.arrow_forward,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              onTap: () => onUseLastPairing(lastPairing!),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _BigChoiceCard(
          icon: Icons.upload,
          title: 'Send files',
          body: 'From this device to another phone or computer.',
          selected: selected == TransferDirection.send,
          onTap: () => onPick(TransferDirection.send),
        ),
        const SizedBox(height: 12),
        _BigChoiceCard(
          icon: Icons.download,
          title: 'Receive files',
          body: 'Wait for another device to send to this one.',
          selected: selected == TransferDirection.receive,
          onTap: () => onPick(TransferDirection.receive),
        ),
      ],
    );
  }
}

class _OtherDeviceStep extends StatelessWidget {
  const _OtherDeviceStep({required this.onPick, required this.selected});
  final ValueChanged<OtherDeviceKind> onPick;
  final OtherDeviceKind? selected;

  static const _items = <_DeviceOption>[
    _DeviceOption(
      kind: OtherDeviceKind.android,
      icon: Icons.android,
      label: 'Android phone or tablet',
    ),
    _DeviceOption(
      kind: OtherDeviceKind.iphone,
      icon: Icons.phone_iphone,
      label: 'iPhone or iPad',
    ),
    _DeviceOption(
      kind: OtherDeviceKind.mac,
      icon: Icons.laptop_mac,
      label: 'Mac',
    ),
    _DeviceOption(
      kind: OtherDeviceKind.windows,
      icon: Icons.laptop_windows,
      label: 'Windows PC',
    ),
    _DeviceOption(
      kind: OtherDeviceKind.notSure,
      icon: Icons.help_outline,
      label: "I'm not sure",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'What is the other device?',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          "We'll pick the simplest way to link the two — no jargon, just the "
          'next thing to tap.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        for (final opt in _items) ...[
          _BigChoiceCard(
            icon: opt.icon,
            title: opt.label,
            body: null,
            selected: selected == opt.kind,
            onTap: () => onPick(opt.kind),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _DeviceOption {
  const _DeviceOption({
    required this.kind,
    required this.icon,
    required this.label,
  });
  final OtherDeviceKind kind;
  final IconData icon;
  final String label;
}

class _BigChoiceCard extends StatelessWidget {
  const _BigChoiceCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? body;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: selected ? theme.colorScheme.primary.withOpacity(0.10) : null,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    if (body != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        body!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstructionsStep extends StatefulWidget {
  const _InstructionsStep({
    required this.self,
    required this.direction,
    required this.other,
    required this.onDone,
  });
  final SelfPlatform self;
  final TransferDirection direction;
  final OtherDeviceKind other;
  final VoidCallback onDone;

  @override
  State<_InstructionsStep> createState() => _InstructionsStepState();
}

class _InstructionsStepState extends State<_InstructionsStep> {
  String? _status;

  Future<void> _openHotspot() async {
    final ok = await SystemSettings.openHotspotSettings();
    if (!mounted) return;
    setState(() {
      _status = ok
          ? 'Opened hotspot settings. Toggle it on, then come back here.'
          : "Couldn't open hotspot settings automatically. Open them yourself "
              'from Android Settings → Network & internet → Hotspot & tethering.';
    });
  }

  Future<void> _openWifi() async {
    final ok = await SystemSettings.openWifiSettings();
    if (!mounted) return;
    setState(() {
      _status = ok
          ? "Opened Wi-Fi settings. Join the other device's hotspot, then "
              'come back here.'
          : "Couldn't open Wi-Fi settings automatically. Open them yourself "
              'from your phone\'s settings.';
    });
  }

  Future<void> _openScanQr() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScanQrPage()),
    );
  }

  Future<void> _openShowQr() async {
    await showPairQrSheet(context);
  }

  Future<void> _switchConnectivity(ConnectivityMode mode) async {
    final state = context.read<AppState>();
    await state.settings.setConnectivityMode(mode);
    if (!mounted) return;
    setState(() {
      _status = mode == ConnectivityMode.hotspot
          ? "Switched LanLink to 'Phone hotspot' mode."
          : "Switched LanLink to 'Wi-Fi' mode.";
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final guide = resolvePairingGuide(
      self: widget.self,
      direction: widget.direction,
      other: widget.other,
    );
    final actions = _actionsFor(widget.self, widget.direction, widget.other);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(guide.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Tap each step on this device when you reach it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < guide.steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    guide.steps[i],
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
        if (guide.tip != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.tips_and_updates_outlined,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    guide.tip!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('Shortcuts on this device', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in actions)
                _ActionChip(
                  icon: a.icon,
                  label: a.label,
                  onTap: () => _runAction(a.id),
                ),
            ],
          ),
        ],
        if (_status != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    color: theme.colorScheme.onPrimaryContainer, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _status!,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text("I'm connected — open LanLink"),
            onPressed: widget.onDone,
          ),
        ),
      ],
    );
  }

  Future<void> _runAction(_ActionId id) async {
    switch (id) {
      case _ActionId.directLink:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DirectLinkPage()),
        );
        break;
      case _ActionId.openHotspot:
        await _openHotspot();
        await _switchConnectivity(ConnectivityMode.hotspot);
        break;
      case _ActionId.openWifi:
        await _openWifi();
        break;
      case _ActionId.scanQr:
        await _openScanQr();
        break;
      case _ActionId.showQr:
        await _openShowQr();
        break;
      case _ActionId.useLan:
        await _switchConnectivity(ConnectivityMode.lan);
        break;
    }
  }

  /// Builds the action shortcuts that make sense for this pairing on
  /// the current device. We don't show actions that can't fire — e.g.
  /// "Open hotspot settings" never appears on iOS or desktop.
  List<_Action> _actionsFor(
      SelfPlatform self, TransferDirection direction, OtherDeviceKind other) {
    final out = <_Action>[];
    final iAmAndroid = self == SelfPlatform.android;
    final iAmMobile = self == SelfPlatform.android || self == SelfPlatform.ios;
    final otherIsMobile =
        other == OtherDeviceKind.android || other == OtherDeviceKind.iphone;
    final bothDesktop = !iAmMobile && !otherIsMobile;

    if (bothDesktop) {
      out.add(const _Action(
        id: _ActionId.useLan,
        icon: Icons.wifi,
        label: "Use Wi-Fi mode",
      ));
      return out;
    }

    if (iAmAndroid) {
      // Android can host. Whether it hosts depends on who else is in
      // the pair.
      final otherIsAndroid = other == OtherDeviceKind.android;
      final iShouldHost =
          !(otherIsAndroid && direction == TransferDirection.send);
      if (iShouldHost) {
        out.add(const _Action(
          id: _ActionId.directLink,
          icon: Icons.bolt,
          label: 'Create direct link (auto)',
        ));
        out.add(const _Action(
          id: _ActionId.openHotspot,
          icon: Icons.wifi_tethering,
          label: 'Open hotspot settings',
        ));
        if (direction == TransferDirection.send) {
          out.add(const _Action(
            id: _ActionId.showQr,
            icon: Icons.qr_code,
            label: 'Show pairing QR',
          ));
        } else {
          out.add(const _Action(
            id: _ActionId.showQr,
            icon: Icons.qr_code,
            label: 'Show pairing QR',
          ));
        }
      } else {
        out.add(const _Action(
          id: _ActionId.openWifi,
          icon: Icons.wifi,
          label: "Open Wi-Fi settings",
        ));
        out.add(const _Action(
          id: _ActionId.scanQr,
          icon: Icons.qr_code_scanner,
          label: 'Scan their QR',
        ));
      }
    } else if (self == SelfPlatform.ios) {
      // iOS can join, can also host manually from Control Center.
      out.add(const _Action(
        id: _ActionId.scanQr,
        icon: Icons.qr_code_scanner,
        label: 'Scan their QR',
      ));
      out.add(const _Action(
        id: _ActionId.showQr,
        icon: Icons.qr_code,
        label: 'Show pairing QR',
      ));
    } else {
      // Desktop sender/receiver with a phone partner. We're on the
      // same Wi-Fi if it's working; offer QR as a fallback.
      out.add(const _Action(
        id: _ActionId.useLan,
        icon: Icons.wifi,
        label: 'Use Wi-Fi mode',
      ));
      out.add(const _Action(
        id: _ActionId.showQr,
        icon: Icons.qr_code,
        label: 'Show pairing QR',
      ));
    }
    return out;
  }
}

enum _ActionId { directLink, openHotspot, openWifi, scanQr, showQr, useLan }

class _Action {
  const _Action({required this.id, required this.icon, required this.label});
  final _ActionId id;
  final IconData icon;
  final String label;
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
