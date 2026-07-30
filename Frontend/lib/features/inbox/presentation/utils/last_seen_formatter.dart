import 'package:intl/intl.dart';

/// Friendly, locale-aware "last seen" text. The time/date parts are formatted
/// with [DateFormat] for the given [locale] (so "3:45 PM" vs "15:45" follows the
/// device), while the surrounding words are plain English — never a raw
/// timestamp. Two shapes: [detailed] for the chat header, [compact] for the
/// conversation list.
class LastSeenFormatter {
  const LastSeenFormatter._();

  /// e.g. "Last seen today at 3:45 PM", "Last seen yesterday at 8:10 PM",
  /// "Last seen 2 days ago", "Last seen 14 Jun 2026".
  static String detailed(DateTime lastSeen, {String? locale, DateTime? now}) {
    final current = now ?? DateTime.now();
    final days = _calendarDaysAgo(lastSeen, current);
    final time = DateFormat.jm(locale).format(lastSeen);
    if (days <= 0) return 'Last seen today at $time';
    if (days == 1) return 'Last seen yesterday at $time';
    if (days < 7) return 'Last seen $days days ago';
    return 'Last seen ${DateFormat.yMMMd(locale).format(lastSeen)}';
  }

  /// e.g. "Last seen just now", "Last seen 10m ago", "Last seen 1h ago",
  /// "Yesterday", "3 days ago", "14 Jun 2026".
  static String compact(DateTime lastSeen, {String? locale, DateTime? now}) {
    final current = now ?? DateTime.now();
    final diff = current.difference(lastSeen);
    final days = _calendarDaysAgo(lastSeen, current);
    if (days <= 0) {
      if (diff.inMinutes < 1) return 'Last seen just now';
      if (diff.inMinutes < 60) return 'Last seen ${diff.inMinutes}m ago';
      return 'Last seen ${diff.inHours}h ago';
    }
    if (days == 1) return 'Yesterday';
    if (days < 7) return '$days days ago';
    return DateFormat.yMMMd(locale).format(lastSeen);
  }

  /// Whole-calendar-day difference (so 11:59pm → 12:01am counts as "yesterday",
  /// not "0 days"), clamped at 0 for future/near-now timestamps.
  static int _calendarDaysAgo(DateTime then, DateTime now) {
    final a = DateTime(now.year, now.month, now.day);
    final b = DateTime(then.year, then.month, then.day);
    final d = a.difference(b).inDays;
    return d < 0 ? 0 : d;
  }
}
