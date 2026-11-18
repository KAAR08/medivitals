/// "just now", "12m ago", "1h 50m ago", "3d ago": how clinical dashboards
/// show the age of an event.
String timeAgo(DateTime then, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(then);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) {
    final m = d.inMinutes.remainder(60);
    return m == 0 ? '${d.inHours}h ago' : '${d.inHours}h ${m}m ago';
  }
  return '${d.inDays}d ago';
}
