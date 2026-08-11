import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// `"2:45 PM"` for today, `"Yesterday"` (localized), otherwise `"Oct 24"`.
/// Used for the conversation list's trailing timestamp.
///
/// The clock and date parts go through [DateFormat] with the active locale
/// rather than being assembled by hand, so a Tamil reader gets Tamil month
/// names and the locale's own 12/24-hour convention.
String formatConversationTime(DateTime dateTime, AppLocalizations l10n) {
  final now = DateTime.now();
  final locale = l10n.localeName;
  if (_isSameDay(dateTime, now)) {
    return DateFormat.jm(locale).format(dateTime);
  }
  if (_isSameDay(dateTime, now.subtract(const Duration(days: 1)))) {
    return l10n.inboxYesterday;
  }
  return DateFormat.MMMd(locale).format(dateTime);
}

/// `"Today"` / `"Yesterday"` (both localized) / `"October 24, 2026"` — used
/// as the Chat Detail thread's date-separator pill text.
String formatDateSeparator(DateTime dateTime, AppLocalizations l10n) {
  final now = DateTime.now();
  if (_isSameDay(dateTime, now)) return l10n.inboxToday;
  if (_isSameDay(dateTime, now.subtract(const Duration(days: 1)))) {
    return l10n.inboxYesterday;
  }
  return DateFormat.yMMMMd(l10n.localeName).format(dateTime);
}
