import '../../../../l10n/app_localizations.dart';

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _twoDigits(int n) => n.toString().padLeft(2, '0');

const _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `"2:45 PM"` for today, `"Yesterday"` (localized), otherwise `"Oct 24"`.
/// Used for the conversation list's trailing timestamp.
String formatConversationTime(DateTime dateTime, AppLocalizations l10n) {
  final now = DateTime.now();
  if (_isSameDay(dateTime, now)) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${_twoDigits(dateTime.minute)} $period';
  }
  if (_isSameDay(dateTime, now.subtract(const Duration(days: 1)))) {
    return l10n.inboxYesterday;
  }
  return '${_shortMonths[dateTime.month - 1]} ${dateTime.day}';
}

/// `"Today"` / `"Yesterday"` (both localized) / `"October 24, 2026"` — used
/// as the Chat Detail thread's date-separator pill text.
String formatDateSeparator(DateTime dateTime, AppLocalizations l10n) {
  final now = DateTime.now();
  if (_isSameDay(dateTime, now)) return l10n.inboxToday;
  if (_isSameDay(dateTime, now.subtract(const Duration(days: 1)))) {
    return l10n.inboxYesterday;
  }
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
}
