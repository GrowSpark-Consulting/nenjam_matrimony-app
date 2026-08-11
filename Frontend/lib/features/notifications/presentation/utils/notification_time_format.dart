import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// True relative time for a notification's trailing timestamp — `"Just
/// now"` / `"2 min ago"` / `"3 hr ago"` for anything within the last 24
/// hours, then `"Yesterday"` (localized), then a short absolute date.
///
/// Unlike `features/inbox/presentation/utils/inbox_date_format.dart`'s
/// `formatConversationTime` (which shows a clock time for "today"), a
/// notification's exact minute rarely matters to the user — how long ago it
/// happened does, so this computes a real elapsed-time string instead of a
/// day-bucketed one.
String formatNotificationTime(DateTime dateTime, AppLocalizations l10n) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);

  if (diff.inSeconds < 60) return l10n.notificationsJustNow;
  if (diff.inMinutes < 60) return l10n.notificationsMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24 && _isSameDay(dateTime, now)) {
    return l10n.notificationsHoursAgo(diff.inHours);
  }
  if (_isSameDay(dateTime, now.subtract(const Duration(days: 1)))) {
    return l10n.notificationsSectionYesterday;
  }
  if (diff.inDays < 7) return l10n.notificationsDaysAgo(diff.inDays);
  return DateFormat.MMMd(l10n.localeName).format(dateTime);
}

/// Which section (Today / Yesterday / Earlier) a notification belongs in.
enum NotificationDateSection { today, yesterday, earlier }

NotificationDateSection notificationSectionFor(DateTime dateTime) {
  final now = DateTime.now();
  if (_isSameDay(dateTime, now)) return NotificationDateSection.today;
  if (_isSameDay(dateTime, now.subtract(const Duration(days: 1)))) {
    return NotificationDateSection.yesterday;
  }
  return NotificationDateSection.earlier;
}

String notificationSectionLabel(NotificationDateSection section, AppLocalizations l10n) {
  switch (section) {
    case NotificationDateSection.today:
      return l10n.notificationsSectionToday;
    case NotificationDateSection.yesterday:
      return l10n.notificationsSectionYesterday;
    case NotificationDateSection.earlier:
      return l10n.notificationsSectionEarlier;
  }
}
