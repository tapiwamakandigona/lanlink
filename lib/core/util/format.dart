/// Format a byte count as a short human-readable string (e.g. "1.4 MB").
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double size = bytes / 1024.0;
  int i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(decimals)} ${units[i]}';
}

/// Format a bytes-per-second number as e.g. "12.4 MB/s".
String formatSpeed(double bytesPerSec) {
  return '${formatBytes(bytesPerSec.round())}/s';
}

/// Format a remaining-time estimate from total bytes, transferred bytes,
/// and a current speed. Returns empty string when the speed is zero.
String formatEta(int totalBytes, int doneBytes, double bytesPerSec) {
  if (bytesPerSec <= 0) return '';
  final remaining = (totalBytes - doneBytes) / bytesPerSec;
  if (!remaining.isFinite || remaining < 0) return '';
  if (remaining < 60) return '${remaining.round()}s';
  final mins = (remaining / 60).floor();
  final secs = (remaining % 60).round();
  return '${mins}m ${secs}s';
}
