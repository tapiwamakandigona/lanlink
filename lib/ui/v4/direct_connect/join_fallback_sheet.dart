import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/wifi_joiner.dart';
import '../theme/tokens.dart';

/// What the user picked on the [JoinFallbackSheet].
enum JoinFallbackAction {
  /// Tier 2: open the system "Add networks" save panel (API 30+).
  addNetwork,

  /// Tier 3: open Wi-Fi settings and join by hand.
  openSettings,
}

/// Bottom sheet shown when the programmatic (Tier-1) hotspot join fails:
/// explains what happened and offers the Tier-2 "save it for me" panel
/// (when the platform has it) and the manual Wi-Fi-settings route, with
/// the password shown big for typing plus a copy button. Pops with the
/// chosen [JoinFallbackAction], or null on cancel/dismiss.
class JoinFallbackSheet extends StatefulWidget {
  const JoinFallbackSheet({
    super.key,
    required this.ssid,
    required this.password,
    required this.canAddNetwork,
    this.reason,
  });

  final String ssid;
  final String password;

  /// Whether the Tier-2 "Add network for me" panel exists on this device.
  final bool canAddNetwork;

  /// Why Tier 1 failed, for honest wording. Null falls back to a generic
  /// explanation.
  final WifiJoinResult? reason;

  @override
  State<JoinFallbackSheet> createState() => _JoinFallbackSheetState();
}

class _JoinFallbackSheetState extends State<JoinFallbackSheet> {
  /// Native channel that copies text with Android 13's "sensitive" clip
  /// flag, so the WPA2 password is hidden from the clipboard-preview
  /// overlay and clipboard listeners. See MainActivity's
  /// "lanlink/clipboard" handler.
  static const MethodChannel _clipboardChannel =
      MethodChannel('lanlink/clipboard');

  /// Inline copy feedback: a SnackBar would render in the Scaffold BEHIND
  /// this modal sheet where the user can't see it.
  bool _copied = false;
  Timer? _copiedReset;

  @override
  void dispose() {
    _copiedReset?.cancel();
    super.dispose();
  }

  Future<void> _copyPassword() async {
    // Prefer the native "sensitive" copy on Android; fall back to the
    // plain clipboard everywhere else (and when the channel is missing,
    // e.g. in widget tests or if the native side ever fails).
    var copied = false;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _clipboardChannel.invokeMethod<bool>(
          'copySensitive',
          <String, String>{'text': widget.password},
        );
        copied = true;
      } on MissingPluginException {
        // No native handler (tests / non-app embeddings): fall through.
      } on PlatformException {
        // Native copy failed: fall through to the plain clipboard.
      }
    }
    if (!copied) {
      await Clipboard.setData(ClipboardData(text: widget.password));
    }
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedReset?.cancel();
    _copiedReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  String get _explanation => switch (widget.reason) {
        WifiJoinResult.timeout =>
          'The Android connection dialog timed out before the network was '
              'joined.',
        WifiJoinResult.declinedOrUnavailable =>
          "Android couldn't find the network, or the connection dialog was "
              'dismissed.',
        _ => "This phone couldn't join the network automatically.",
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      // Scrollable so the tall password + three actions never overflow on
      // small screens / split-screen windows.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            VSpace.x6, VSpace.x5, VSpace.x6, VSpace.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Couldn\'t join "${widget.ssid}" automatically',
              style: VType.heading.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: VSpace.x2),
            Text(
              '$_explanation You can still connect — pick an option below, '
              'then come back to LanLink.',
              style: VType.body.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: VSpace.x5),
            Container(
              padding: const EdgeInsets.all(VSpace.x4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: VRadius.mdAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Network',
                    style: VType.label.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    widget.ssid,
                    style: VType.bodyStrong.copyWith(color: scheme.onSurface),
                  ),
                  // Open networks (empty password) get no password row —
                  // an empty line plus a copy button would only confuse.
                  if (widget.password.isNotEmpty) ...[
                    const SizedBox(height: VSpace.x3),
                    Text(
                      'Password',
                      style:
                          VType.label.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            widget.password,
                            style:
                                VType.display.copyWith(color: scheme.onSurface),
                          ),
                        ),
                        if (_copied)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: VSpace.x2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_rounded,
                                    size: 18, color: scheme.primary),
                                const SizedBox(width: VSpace.x1),
                                Text(
                                  'Copied',
                                  style: VType.label
                                      .copyWith(color: scheme.primary),
                                ),
                              ],
                            ),
                          )
                        else
                          IconButton(
                            tooltip: 'Copy password',
                            icon: const Icon(Icons.copy_rounded),
                            onPressed: _copyPassword,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: VSpace.x5),
            if (widget.canAddNetwork) ...[
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(JoinFallbackAction.addNetwork),
                icon: const Icon(Icons.wifi_find_rounded),
                label: const Text('Add network for me'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
              const SizedBox(height: VSpace.x3),
            ],
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(JoinFallbackAction.openSettings),
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Open Wi-Fi settings'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: VSpace.x2),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
