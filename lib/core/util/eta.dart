// Plain-English remaining-time helpers used by the progress UI.
//
// We deliberately avoid `12m 7s` style readouts in v3.2.0 because they
// look like a debug log. Instead we say "About 30 seconds left",
// "About 5 minutes left", etc. — the kind of language a non-technical
// user can read at a glance.

/// Returns a plain-English ETA string from total/done bytes + current
/// throughput. Returns empty string when the speed is non-positive or
/// the remainder is zero/negative.
String plainEnglishEta({
  required int totalBytes,
  required int doneBytes,
  required double bytesPerSec,
}) {
  if (bytesPerSec <= 0) return '';
  final remaining = (totalBytes - doneBytes) / bytesPerSec;
  if (!remaining.isFinite || remaining <= 0) return '';
  return _humanise(remaining);
}

String _humanise(double seconds) {
  if (seconds < 5) return 'Almost done';
  if (seconds < 90) {
    final rounded = _roundTo(seconds.round(), 5);
    return 'About $rounded seconds left';
  }
  if (seconds < 60 * 60) {
    final minutes = (seconds / 60).round();
    final unit = minutes == 1 ? 'minute' : 'minutes';
    return 'About $minutes $unit left';
  }
  final hours = seconds / 3600;
  if (hours < 10) {
    final h = hours.toStringAsFixed(1);
    return 'About $h hours left';
  }
  return 'Over ${hours.floor()} hours left';
}

int _roundTo(int value, int step) {
  if (step <= 1) return value;
  final r = ((value + step ~/ 2) ~/ step) * step;
  return r < step ? step : r;
}

/// Returns true when the recent throughput indicates a struggling
/// connection — currently <100 KB/s sustained.
bool isSlowSpeed(double bytesPerSec) =>
    bytesPerSec > 0 && bytesPerSec < 100 * 1024;
