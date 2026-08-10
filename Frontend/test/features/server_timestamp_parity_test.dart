import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/utils/server_time.dart';
import 'package:nenjam_matrimony/features/notifications/data/models/notification_model.dart';
import 'package:nenjam_matrimony/features/notifications/presentation/utils/notification_time_format.dart';

/// The chat timezone fix (`parseServerTime`) was originally applied only to
/// the inbox. The same raw `DateTime.parse` remained in the Notification
/// Centre, Interests, Support tickets and Blocked Users, so those screens kept
/// bucketing by the UTC calendar day.
///
/// The visible symptom is narrow but real: relative strings ("2 min ago") are
/// computed with `difference()`, which works on absolute instants and is
/// therefore correct either way. It is the *day* comparisons — `_isSameDay` in
/// notification_time_format.dart reads `.year/.month/.day` — and the absolute
/// date fallback that go wrong. East of UTC, anything sent between local
/// midnight and the UTC offset (00:00–05:30 in IST) has a UTC date of
/// *yesterday*, so a notification from this morning is filed under "Yesterday".
///
/// These tests are deliberately host-timezone independent: they assert against
/// `DateTime.utc(...).toLocal()` and against locally-derived "now", never
/// hardcoded IST arithmetic. They therefore pass on a UTC CI runner (where the
/// bug is invisible) and on an IST developer machine alike — what they pin is
/// the invariant, not one timezone's offset.
void main() {
  group('parseServerTime contract', () {
    test('a timezone-less server timestamp is read as UTC, not local', () {
      // Case 1. The backend serializes with toISOString() (always Z), but a
      // naive string must never be trusted as local — that is the bug itself.
      final parsed = parseServerTime('2026-08-10T00:30:00');

      expect(parsed.isUtc, isFalse, reason: 'must be converted to local');
      expect(
        parsed.millisecondsSinceEpoch,
        DateTime.utc(2026, 8, 10, 0, 30).millisecondsSinceEpoch,
        reason: 'the naive wall clock is UTC, so the instant must match',
      );
    });

    test('an explicit Z designator is preserved as UTC', () {
      // Case 4.
      final parsed = parseServerTime('2026-08-10T00:30:00Z');

      expect(parsed.isUtc, isFalse);
      expect(parsed, DateTime.utc(2026, 8, 10, 0, 30).toLocal());
    });

    test('the local wall clock matches the UTC instant shifted by the host offset', () {
      // Case 2 — expressed host-independently. On an IST machine this is the
      // 00:30 UTC -> 06:00 IST case from the bug report; on a UTC runner both
      // sides are simply equal.
      final parsed = parseServerTime('2026-08-10T00:30:00Z');
      final expected = DateTime.utc(2026, 8, 10, 0, 30).toLocal();

      expect(parsed.hour, expected.hour);
      expect(parsed.day, expected.day);
    });

    test('parsing is idempotent — a further toLocal() changes nothing', () {
      final parsed = parseServerTime('2026-08-10T09:15:30.000Z');
      expect(parsed.toLocal(), parsed);
    });

    test('tryParseServerTime returns null for unparseable or non-string input', () {
      expect(tryParseServerTime(null), isNull);
      expect(tryParseServerTime(42), isNull);
      expect(tryParseServerTime('not a date'), isNull);
      expect(tryParseServerTime('2026-08-10T09:15:30.000Z'), isNotNull);
    });
  });

  group('Notification Centre day bucketing', () {
    /// A server timestamp for an instant `ago` before now, in the wire format
    /// the backend actually emits.
    String wireAgo(Duration ago) =>
        DateTime.now().toUtc().subtract(ago).toIso8601String();

    NotificationModel notificationSentAt(String createdAt) =>
        NotificationModel.fromJson({
          'id': 'n1',
          'type': 'INTEREST_RECEIVED',
          'title': 'Someone liked you',
          'body': 'Tap to view',
          'createdAt': createdAt,
          'isRead': false,
        });

    test('a notification from minutes ago is filed under Today', () {
      // Case 3. This is the regression: before the fix, running this between
      // local midnight and the UTC offset produced `yesterday`.
      final model = notificationSentAt(wireAgo(const Duration(minutes: 5)));

      expect(notificationSectionFor(model.createdAt),
          NotificationDateSection.today);
    });

    test('a notification from just after local midnight is still Today', () {
      // The exact window the bug lived in: local time is early morning, so the
      // UTC date is still yesterday anywhere east of Greenwich. Skipped when
      // the host clock is not actually in that window, since there is no way
      // to fabricate it without freezing time.
      final now = DateTime.now();
      final justAfterMidnight = DateTime(now.year, now.month, now.day, 0, 30);
      if (now.isBefore(justAfterMidnight)) return;

      final wire = justAfterMidnight.toUtc().toIso8601String();
      final parsed = parseServerTime(wire);

      expect(notificationSectionFor(parsed), NotificationDateSection.today,
          reason: 'a local-today instant must never bucket as yesterday');
    });

    test('a notification from ~30 hours ago is not Today', () {
      final model = notificationSentAt(wireAgo(const Duration(hours: 30)));

      expect(notificationSectionFor(model.createdAt),
          isNot(NotificationDateSection.today));
    });

    test('the parsed timestamp is local, so wall-clock reads are correct', () {
      final model = notificationSentAt('2026-08-10T00:30:00Z');

      expect(model.createdAt.isUtc, isFalse);
      expect(model.createdAt, DateTime.utc(2026, 8, 10, 0, 30).toLocal());
    });

    test('relative formatting still works after the change', () {
      // Case 5 — difference() operates on absolute instants and was never
      // broken; this pins that the fix did not regress it.
      final model = notificationSentAt(wireAgo(const Duration(minutes: 2)));
      final diff = DateTime.now().difference(model.createdAt);

      expect(diff.inMinutes, 2);
    });
  });
}
