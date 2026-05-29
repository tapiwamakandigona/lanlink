/// Coarse signal level shown in the home AppBar. We don't have a real
/// signal-strength readout cross-platform, so we infer it from how many
/// peers we can see right now: zero is "no one nearby", one or two is
/// "OK", three or more is "Strong". A peer count of one with a slow
/// transfer is downgraded to "weak" by the progress widget separately.
enum ConnectionQuality { none, weak, fair, strong }

ConnectionQuality qualityForPeerCount(int peerCount) {
  if (peerCount <= 0) return ConnectionQuality.none;
  if (peerCount == 1) return ConnectionQuality.fair;
  if (peerCount == 2) return ConnectionQuality.fair;
  return ConnectionQuality.strong;
}

extension ConnectionQualityLabel on ConnectionQuality {
  String get label {
    switch (this) {
      case ConnectionQuality.none:
        return 'No devices yet';
      case ConnectionQuality.weak:
        return 'Weak connection';
      case ConnectionQuality.fair:
        return 'Connected';
      case ConnectionQuality.strong:
        return 'Strong connection';
    }
  }

  /// Number of filled bars (out of 3) for the indicator widget.
  int get bars {
    switch (this) {
      case ConnectionQuality.none:
        return 0;
      case ConnectionQuality.weak:
        return 1;
      case ConnectionQuality.fair:
        return 2;
      case ConnectionQuality.strong:
        return 3;
    }
  }
}
