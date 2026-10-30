import 'package:intl/intl.dart';

final _time = DateFormat.jm();          // 3:05 PM
final _dayLong = DateFormat('EEEE, MMMM d y');
final _dayShort = DateFormat('EEE, MMM d');

String fmtTime(DateTime t) => _time.format(t);
String fmtDayLong(DateTime d) => _dayLong.format(d);
String fmtDayShort(DateTime d) => _dayShort.format(d);

/// "just now", "5 min ago", "an hour ago", "3 hours ago", "yesterday", then the date.
String fmtRelative(DateTime? t, {DateTime? now}) {
  if (t == null) return 'never';
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes < 1 ? 1 : d.inMinutes} min ago';
  if (d.inHours < 2) return 'an hour ago';
  if (d.inHours < 24) return '${d.inHours} hours ago';
  if (sameDay(t, n.subtract(const Duration(days: 1)))) return 'yesterday';
  return fmtDayShort(t);
}

/// "Last seen 5 min ago" — when the device last reported in.
String fmtLastSeen(DateTime? t, {DateTime? now}) => t == null ? 'Not seen yet' : 'Last seen ${fmtRelative(t, now: now)}';

String fmtDuration(Duration d) {
  if (d.inMinutes < 1) return '${d.inSeconds} s';
  if (d.inHours < 1) return '${d.inMinutes} min';
  final m = d.inMinutes % 60;
  return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
}

String fmtKm(double meters) => meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1)} km';

String fmtSpeed(double kmh) => '${kmh < 10 ? kmh.toStringAsFixed(1) : kmh.round()} km/h';

/// 09XXXXXXXXX, 639XXXXXXXXX or +639XXXXXXXXX → +639XXXXXXXXX; anything else → null.
String? normalizePhPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (RegExp(r'^\+639\d{9}$').hasMatch(digits)) return digits;
  if (RegExp(r'^09\d{9}$').hasMatch(digits)) return '+63${digits.substring(1)}';
  if (RegExp(r'^639\d{9}$').hasMatch(digits)) return '+$digits';
  return null;
}

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Midnight of [t]'s day — the stable key for per-day providers.
DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);
