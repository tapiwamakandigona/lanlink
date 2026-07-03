import 'package:flutter/material.dart';

import 'v4.dart';

/// The v4 component gallery: every component in every state, on one page.
///
/// This is the review surface for the design system and the reference for
/// the app-shell stage. Run it standalone with [V4GalleryApp], or embed
/// [V4GalleryPage] under any `EmberTheme`.
class V4GalleryApp extends StatelessWidget {
  const V4GalleryApp({super.key, this.themeMode = ThemeMode.light});

  /// Which theme to preview.
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LanLink v4 gallery',
      debugShowCheckedModeBanner: false,
      theme: EmberTheme.light(),
      darkTheme: EmberTheme.dark(),
      themeMode: themeMode,
      home: const V4GalleryPage(),
    );
  }
}

/// The gallery page itself. Content is width-capped at 720 so it reads
/// well from phone (390) to desktop (1200+).
class V4GalleryPage extends StatelessWidget {
  const V4GalleryPage({super.key});

  static const _peers = [
    RadarPeerData(
        id: 'fp-otter',
        name: 'Purple-Otter',
        deviceType: DeviceType.laptop,
        verified: true),
    RadarPeerData(
        id: 'fp-heron', name: 'Sunny-Heron', deviceType: DeviceType.phone),
    RadarPeerData(
        id: 'fp-badger',
        name: 'Quiet-Badger',
        deviceType: DeviceType.desktop,
        verified: true),
    RadarPeerData(
        id: 'fp-finch', name: 'Copper-Finch', deviceType: DeviceType.tablet),
    RadarPeerData(
        id: 'fp-fox', name: 'Marmalade-Fox', deviceType: DeviceType.phone),
  ];

  @override
  Widget build(BuildContext context) {
    void noop() {}
    return Scaffold(
      appBar: AppBar(title: const Text('v4 · Ember on Paper')),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  VSpace.x5, VSpace.x4, VSpace.x5, VSpace.x16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _SectionHeader('Two-verb home'),
                  TwoVerbHome(
                    deviceName: 'Marmalade-Fox',
                    onSend: noop,
                    onReceive: noop,
                    sessionStrip: SessionCard(
                      data: const SessionCardData(
                        title: '14 photos',
                        fileCount: 14,
                        totalSize: '48 MB',
                        peerName: 'Purple-Otter',
                        status: SessionStatus.transferring,
                        progress: 0.62,
                        speed: '34 MB/s',
                        eta: 'about 20 sec left',
                      ),
                      onStop: noop,
                    ),
                  ),
                  const _SectionHeader('Device radar'),
                  DeviceRadar(peers: _peers, onPeerTap: (_) {}),
                  const SizedBox(height: VSpace.x5),
                  DeviceRadar(peers: const [], onPeerTap: (_) {}),
                  const SizedBox(height: VSpace.x4),
                  DeviceRadar(
                      peers: const [], searching: false, onPeerTap: (_) {}),
                  const _SectionHeader('Session card — all states'),
                  SessionCard(
                    data: const SessionCardData(
                      title: 'holiday-video.mp4',
                      totalSize: '1.2 GB',
                      peerName: 'Purple-Otter',
                      status: SessionStatus.waiting,
                    ),
                    onStop: noop,
                  ),
                  const SizedBox(height: VSpace.x3),
                  SessionCard(
                    data: const SessionCardData(
                      title: 'holiday-video.mp4',
                      totalSize: '1.2 GB',
                      peerName: 'Purple-Otter',
                      status: SessionStatus.transferring,
                      progress: 0.38,
                      speed: '41 MB/s',
                      eta: 'about 2 min left',
                    ),
                    onStop: noop,
                  ),
                  const SizedBox(height: VSpace.x3),
                  SessionCard(
                    data: const SessionCardData(
                      title: '14 photos',
                      fileCount: 14,
                      totalSize: '48 MB',
                      peerName: 'Purple-Otter',
                      status: SessionStatus.sent,
                    ),
                    onDismiss: noop,
                  ),
                  const SizedBox(height: VSpace.x3),
                  SessionCard(
                    data: const SessionCardData(
                      title: 'project-archive.zip',
                      totalSize: '620 MB',
                      peerName: 'Quiet-Badger',
                      status: SessionStatus.failed,
                      errorHint: 'The connection was lost. '
                          'Both devices need to stay on the same Wi-Fi.',
                    ),
                    onRetry: noop,
                    onDismiss: noop,
                  ),
                  const SizedBox(height: VSpace.x3),
                  SessionCard(
                    data: const SessionCardData(
                      title: 'soundtrack.flac',
                      totalSize: '86 MB',
                      peerName: 'Sunny-Heron',
                      status: SessionStatus.cancelled,
                    ),
                    onDismiss: noop,
                  ),
                  const _SectionHeader('Consent sheet'),
                  _SheetPreview(
                    child: ConsentSheet(
                      data: const ConsentRequestData(
                        senderName: 'Purple-Otter',
                        fileCount: 14,
                        totalSize: '48 MB',
                        verified: true,
                        previewFileNames: [
                          'IMG_2041.jpg',
                          'IMG_2042.jpg',
                          'IMG_2043.jpg',
                        ],
                      ),
                      onAccept: noop,
                      onDecline: noop,
                    ),
                  ),
                  const SizedBox(height: VSpace.x4),
                  _SheetPreview(
                    child: ConsentSheet(
                      data: const ConsentRequestData(
                        senderName: 'Sunny-Heron',
                        fileCount: 1,
                        totalSize: '1.2 GB',
                        previewFileNames: ['holiday-video.mp4'],
                      ),
                      onAccept: noop,
                      onDecline: noop,
                    ),
                  ),
                  const _SectionHeader('QR — receive shows, send scans'),
                  LayoutBuilder(builder: (context, c) {
                    const qr = QrDisplayPanel(
                      payload: 'lanlink://connect/demo-gallery-payload',
                      deviceName: 'Marmalade-Fox',
                      size: 160,
                    );
                    const scan = QrScanFrame();
                    if (c.maxWidth < 560) {
                      return const Column(children: [
                        qr,
                        SizedBox(height: VSpace.x5),
                        scan,
                      ]);
                    }
                    return const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: qr),
                        SizedBox(width: VSpace.x5),
                        Expanded(child: scan),
                      ],
                    );
                  }),
                  const _SectionHeader('Badges'),
                  const Wrap(
                    spacing: VSpace.x4,
                    runSpacing: VSpace.x3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      VerifiedBadge(),
                      VerifiedBadge(compact: true),
                      SessionStatusChip(status: SessionStatus.waiting),
                      SessionStatusChip(status: SessionStatus.transferring),
                      SessionStatusChip(status: SessionStatus.sent),
                      SessionStatusChip(status: SessionStatus.failed),
                      SessionStatusChip(status: SessionStatus.cancelled),
                    ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: VSpace.x10, bottom: VSpace.x4),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: VType.label.copyWith(
              color: scheme.primary,
              letterSpacing: 1.2,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: VSpace.x3),
          Expanded(child: Divider(color: scheme.outlineVariant)),
        ],
      ),
    );
  }
}

/// Frames sheet-style components so they read as sheets inside the
/// scrolling gallery.
class _SheetPreview extends StatelessWidget {
  const _SheetPreview({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: VRadius.lgAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
