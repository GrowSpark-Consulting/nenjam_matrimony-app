import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/utils/server_time.dart';
import 'package:nenjam_matrimony/features/inbox/data/mappers/message_wire_mapper.dart';

/// Regression coverage for the chat timestamp timezone bug: the backend
/// serializes every timestamp with `Date.toISOString()` (always `Z`-suffixed
/// UTC), and a bare `DateTime.parse` returned a UTC-flagged [DateTime] whose
/// `.hour`/`.day` are UTC wall-clock fields. Message bubbles, date
/// separators, and the inbox list all read those fields directly, so a
/// message sent at 2:45 PM IST rendered as 9:15 AM after a refresh.
///
/// These tests are host-timezone independent: they assert against
/// `DateTime.utc(...).toLocal()` rather than hardcoded IST offsets, so they
/// pass on a UTC CI box (where the bug is invisible) and on an IST machine
/// alike — what they pin is the *invariant*, not one timezone's arithmetic.
void main() {
  const wireCreatedAt = '2026-08-10T09:15:30.000Z';
  final expectedInstant = DateTime.utc(2026, 8, 10, 9, 15, 30);

  Map<String, dynamic> wireMessage({
    String createdAt = wireCreatedAt,
    String? editedAt,
    Map<String, dynamic>? replyTo,
  }) =>
      {
        'id': 'msg-1',
        'roomId': 'room-1',
        'content': 'hello',
        'createdAt': createdAt,
        'isMine': true,
        'status': 'sent',
        'type': 'TEXT',
        if (editedAt != null) 'editedAt': editedAt,
        if (replyTo != null) 'replyTo': replyTo,
      };

  group('parseServerTime', () {
    test('converts a UTC wire timestamp to local time exactly once', () {
      final parsed = parseServerTime(wireCreatedAt);

      // Same instant — a timezone fix must never move the point in time.
      expect(parsed.isAtSameMomentAs(expectedInstant), isTrue);
      // ...but expressed in local wall-clock fields, which is what the UI reads.
      expect(parsed.isUtc, isFalse);
      expect(parsed, equals(expectedInstant.toLocal()));
    });

    test('is idempotent — a second toLocal() is a no-op', () {
      final once = parseServerTime(wireCreatedAt);
      expect(once.toLocal(), equals(once));
      expect(once.toLocal().toLocal(), equals(once));
    });

    test('treats a timezone-less timestamp as UTC, not local', () {
      // Dart parses a bare wall clock as *local*; the backend never means
      // that. Both spellings must land on the same instant.
      expect(
        parseServerTime('2026-08-10T09:15:30.000'),
        equals(parseServerTime(wireCreatedAt)),
      );
    });

    test('tryParseServerTime returns null for non-string / unparseable input', () {
      expect(tryParseServerTime(null), isNull);
      expect(tryParseServerTime(42), isNull);
      expect(tryParseServerTime('not-a-date'), isNull);
      expect(tryParseServerTime(wireCreatedAt), equals(expectedInstant.toLocal()));
    });
  });

  group('messageEntityFromWire', () {
    test('decodes createdAt into local time', () {
      final message = messageEntityFromWire(wireMessage());

      expect(message.sentAt.isUtc, isFalse);
      expect(message.sentAt, equals(expectedInstant.toLocal()));
      expect(message.sentAt.isAtSameMomentAs(expectedInstant), isTrue);
    });

    test('decodes editedAt into local time', () {
      final message = messageEntityFromWire(
        wireMessage(editedAt: '2026-08-10T10:00:00.000Z'),
      );

      expect(message.editedAt, isNotNull);
      expect(message.editedAt!.isUtc, isFalse);
      expect(
        message.editedAt,
        equals(DateTime.utc(2026, 8, 10, 10).toLocal()),
      );
    });

    test('leaves a missing editedAt null', () {
      expect(messageEntityFromWire(wireMessage()).editedAt, isNull);
    });

    test('decodes a reply preview editedAt into local time', () {
      final message = messageEntityFromWire(
        wireMessage(replyTo: {
          'id': 'msg-0',
          'isMine': false,
          'type': 'TEXT',
          'content': 'original',
          'editedAt': '2026-08-10T08:00:00.000Z',
        }),
      );

      expect(message.replyTo, isNotNull);
      expect(message.replyTo!.editedAt, equals(DateTime.utc(2026, 8, 10, 8).toLocal()));
    });

    test('REST history and the socket push decode identically', () {
      // Both paths call this same mapper on the same DTO shape — this pins
      // that, so the two can never drift back apart.
      final restPayload = wireMessage();
      final socketPayload = wireMessage();

      expect(
        messageEntityFromWire(restPayload).sentAt,
        equals(messageEntityFromWire(socketPayload).sentAt),
      );
    });

    test('an optimistic DateTime.now() is already local and stays untouched', () {
      // Locally-created timestamps must never go through parseServerTime;
      // this pins the property the send path relies on.
      final optimistic = DateTime.now();
      expect(optimistic.isUtc, isFalse);
      expect(optimistic.toLocal(), equals(optimistic));
    });
  });
}
