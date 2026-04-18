/// Utility functions shared across the entire app.

String formatCount(int n) {
  if (n >= 1_000_000_000) return '${(n / 1_000_000_000).toStringAsFixed(1)}B';
  if (n >= 1_000_000)     return '${(n / 1_000_000).toStringAsFixed(1)}M';
  if (n >= 1_000)         return '${(n / 1_000).toStringAsFixed(1)}K';
  return '$n';
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String formatFileSize(int bytes) {
  if (bytes < 1024)            return '${bytes} B';
  if (bytes < 1024 * 1024)     return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// Returns a Date string appropriate for display (Today, Yesterday, or date).
String formatUploadDate(DateTime dt) {
  final now   = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date  = DateTime(dt.year, dt.month, dt.day);
  final diff  = today.difference(date).inDays;
  if (diff == 0)  return 'Today';
  if (diff == 1)  return 'Yesterday';
  if (diff < 7)   return '$diff days ago';
  if (diff < 30)  return '${(diff / 7).floor()} weeks ago';
  if (diff < 365) return '${(diff / 30).floor()} months ago';
  return '${(diff / 365).floor()} years ago';
}
