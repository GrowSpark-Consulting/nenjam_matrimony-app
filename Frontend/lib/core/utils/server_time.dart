/// Nenjam Matrimony — Server timestamp parsing
///
/// The single place a backend-supplied timestamp becomes a [DateTime] the UI
/// can read wall-clock fields off (`.hour`, `.day`, …).
///
/// The backend serializes every timestamp with `Date.toISOString()`, so the
/// wire value is always UTC — e.g. `"2026-08-10T09:15:00.000Z"`. A bare
/// `DateTime.parse` on that returns a UTC-flagged [DateTime], whose `.hour`
/// is the *UTC* hour; rendering it directly shows a message sent at 2:45 PM
/// IST as 9:15 AM. Every server timestamp must therefore be converted to
/// local time, and this is where that happens — exactly once, at the
/// decode boundary.
///
/// The invariant these helpers establish: **every [DateTime] that leaves the
/// data layer is already local.** Nothing downstream (entities, providers,
/// formatters, widgets) may call `.toLocal()` again, and nothing may render
/// a timestamp that did not come through here. Locally-created times
/// (`DateTime.now()` for an optimistic message) are already local and must
/// not be passed through this at all.
library;

/// Parses an ISO-8601 timestamp from the backend into **local** time.
///
/// A string carrying a timezone designator (`Z` or an explicit offset) is
/// parsed by Dart into UTC and converted from there. A string with *no*
/// designator is reinterpreted as UTC rather than trusted as local — a naive
/// wall clock from this backend is always UTC, and treating it as local is
/// precisely the bug this function exists to prevent.
DateTime parseServerTime(String value) {
  final parsed = DateTime.parse(value);
  return (parsed.isUtc ? parsed : _asUtc(parsed)).toLocal();
}

/// [parseServerTime] for a nullable/untyped wire field — returns null for
/// anything that isn't a parseable ISO-8601 string, matching the
/// "drop rather than throw" stance the chat wire mappers already take.
DateTime? tryParseServerTime(dynamic value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  return (parsed.isUtc ? parsed : _asUtc(parsed)).toLocal();
}

/// Reinterprets a timezone-less parse result's wall-clock fields as UTC.
DateTime _asUtc(DateTime naive) => DateTime.utc(
      naive.year,
      naive.month,
      naive.day,
      naive.hour,
      naive.minute,
      naive.second,
      naive.millisecond,
      naive.microsecond,
    );
