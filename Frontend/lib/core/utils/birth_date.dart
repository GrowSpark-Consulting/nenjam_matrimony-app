/// Nenjam Matrimony — the date-of-birth rule.
///
/// One definition of "is this a date of birth a profile may carry", shared by
/// every screen that asks for one (onboarding's Your Name step, the Edit
/// Profile wizard's Basic Info step), by the widget that collects it
/// (`NmBirthDateField`) and by `PostAuthDestination`, which reconstructs the
/// answer to decide whether the step has been satisfied. Stating it once is
/// what stops a screen from accepting a date another screen — or the backend
/// — would reject.
///
/// It is mirrored by hand on the server in
/// `backend/apps/api/src/modules/profiles/validation/birth-date.ts`; keep the
/// two in step. The server is the authority, and re-validates every value
/// this file lets through.
///
/// A date of birth is a **calendar date**, not a timestamp: it has no time of
/// day and no timezone. Nothing here goes through `parseServerTime` — that
/// helper converts a real instant to local time, which for a birthdate would
/// shift it a day whenever the offset crosses midnight. The wire form is
/// `YYYY-MM-DD`; see [birthDateFromWire] and [birthDateToWire].
library;

/// Youngest a member may be, in whole years.
///
/// Compared against the *complete* date — see [BirthDateInput.latestAllowed].
/// A year-difference test would let someone whose birthday is still weeks
/// away register a year early.
const int kMinimumProfileAgeYears = 21;

// There is deliberately no maximum age and no earliest year.
//
// A `kEarliestBirthYear = 1950` floor briefly stood here, inherited from the
// `firstDate: DateTime(1950)` bound of the calendar pickers the typed field
// replaced. That bound was a picker's scroll range, not a product rule, and
// keeping it as validation invented a maximum age of 76 on a platform whose
// members include widowed and divorced people remarrying later in life — and
// would have locked an existing member holding a pre-1950 date out of saving
// their own profile. The server carries the same note.
//
// The rules are exactly: a real calendar date, a four-digit year, in the past,
// and at least `kMinimumProfileAgeYears` ago.

/// Why a typed date of birth was rejected. Ordered as the member reads the
/// boxes across the row, so the first thing wrong is the first thing said.
enum BirthDateError {
  /// The Day box: empty, non-numeric, or outside 1-31.
  day,

  /// The Month box: empty, non-numeric, or outside 1-12.
  month,

  /// The Year box: empty, or not four digits.
  year,

  /// Three plausible parts that name no real day — 31 February, 29 February
  /// of a common year, 31 April.
  invalidDate,

  /// A real date that has not happened yet.
  future,

  /// A real, past date, but under [kMinimumProfileAgeYears].
  tooYoung,
}

/// A date of birth as the member is typing it: three digit strings, any of
/// which may be blank, partial or nonsense.
///
/// Immutable, and plain Dart — no widget, no `BuildContext`, no Flutter
/// import — so the rule is testable on its own and reusable by anything that
/// needs to ask "has this step been answered?" without building the screen.
class BirthDateInput {
  /// Exactly as typed — not normalised, so a half-entered `1` is not silently
  /// read as the 1st.
  final String day;
  final String month;
  final String year;

  const BirthDateInput({this.day = '', this.month = '', this.year = ''});

  /// The three boxes filled in from a date already stored, zero-padded the
  /// way the member would have typed it — reopening a step shows the answer
  /// given rather than three empty boxes.
  factory BirthDateInput.fromDate(DateTime? date) {
    if (date == null) return const BirthDateInput();
    return BirthDateInput(
      day: date.day.toString().padLeft(2, '0'),
      month: date.month.toString().padLeft(2, '0'),
      year: date.year.toString(),
    );
  }

  BirthDateInput copyWith({String? day, String? month, String? year}) {
    return BirthDateInput(
      day: day ?? this.day,
      month: month ?? this.month,
      year: year ?? this.year,
    );
  }

  /// Whether the member has typed anything at all. Lets a screen stay quiet
  /// on a blank form and explain itself only once there is something to
  /// explain.
  bool get isTouched =>
      day.trim().isNotEmpty ||
      month.trim().isNotEmpty ||
      year.trim().isNotEmpty;

  /// The date the three boxes name, or null when they name none.
  ///
  /// Null exactly when [error] is non-null; the two are computed from the
  /// same pass, so a screen can never show "valid" and an error at once.
  DateTime? get date => _evaluate(DateTime.now()).date;

  /// Why [date] is null, or null when the date is fine. Every rule applied —
  /// this is the submission-time check.
  BirthDateError? get error => _evaluate(DateTime.now()).error;

  /// The real, past calendar date the boxes name, **ignoring the age floor**.
  ///
  /// For asking "has this question been answered?" rather than "may this be
  /// submitted?" — the two are different questions, and routing asks the
  /// first. A member who registered when the floor was 18 has a real date of
  /// birth they cannot change; treating it as unanswered would send them back
  /// to a step no answer of theirs can satisfy, forever. The server draws the
  /// same line: `isMatchableFromDraft` parses the stored date, and only
  /// `BasicDetailsDto` applies the floor, to values arriving now.
  DateTime? get calendarDate =>
      _evaluate(DateTime.now(), applyAgeFloor: false).date;

  /// [error], but silent about a box the member has not finished typing.
  ///
  /// A Day box holding `1` is on its way to the 15th, not a mistake; a Year
  /// box holding `199` is on its way to 1998. Complaining at every keystroke
  /// would make the field shout at someone doing nothing wrong, so a part is
  /// only judged once it holds its full width of digits (2, 2 and 4), and the
  /// whole-date rules — impossible dates, the future, the age floor — only
  /// once all three do.
  BirthDateError? get liveError {
    if (!isTouched) return null;
    final error = _evaluate(DateTime.now()).error;
    if (error == null) return null;

    final dayDone = day.trim().length >= 2;
    final monthDone = month.trim().length >= 2;
    final yearDone = year.trim().length >= 4;

    return switch (error) {
      BirthDateError.day => dayDone ? error : null,
      BirthDateError.month => monthDone ? error : null,
      BirthDateError.year => yearDone ? error : null,
      _ => dayDone && monthDone && yearDone ? error : null,
    };
  }

  /// The rule, evaluated against [asOf] rather than the wall clock. Exposed
  /// so tests can pin "today": an age boundary that only misbehaves on one
  /// particular day of the year is not testable otherwise.
  BirthDateResult evaluateAsOf(DateTime asOf) => _evaluate(asOf);

  BirthDateResult _evaluate(DateTime asOf, {bool applyAgeFloor = true}) {
    final d = _parsePart(day, 2);
    if (d == null || d < 1 || d > 31) {
      return const BirthDateResult(error: BirthDateError.day);
    }
    final m = _parsePart(month, 2);
    if (m == null || m < 1 || m > 12) {
      return const BirthDateResult(error: BirthDateError.month);
    }
    final y = _parsePart(year, 4);
    // Four digits exactly: `98` is not 1998, and guessing a century for a
    // birthdate is how someone ends up two thousand years old.
    if (y == null || year.trim().length != 4) {
      return const BirthDateResult(error: BirthDateError.year);
    }
    final candidate = DateTime(y, m, d);
    // DateTime(2003, 2, 29) is 1 March — a rollover, not the date typed.
    if (candidate.year != y || candidate.month != m || candidate.day != d) {
      return const BirthDateResult(error: BirthDateError.invalidDate);
    }

    final today = DateTime(asOf.year, asOf.month, asOf.day);
    // Today included: nobody is born into the profile they are filling in.
    if (!candidate.isBefore(today)) {
      return const BirthDateResult(error: BirthDateError.future);
    }
    if (applyAgeFloor && candidate.isAfter(latestAllowed(asOf))) {
      return const BirthDateResult(error: BirthDateError.tooYoung);
    }
    return BirthDateResult(date: candidate);
  }

  /// A single box's digits, or null when it is blank, wider than [maxDigits],
  /// or holds anything but digits.
  static int? _parsePart(String raw, int maxDigits) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > maxDigits) return null;
    if (!RegExp(r'^\d+$').hasMatch(trimmed)) return null;
    return int.parse(trimmed);
  }

  /// The most recent date of birth the rule accepts: [kMinimumProfileAgeYears]
  /// ago to the day. Someone born the day after this is a day short of the
  /// floor and is rejected, which is the whole point of comparing complete
  /// dates rather than years.
  static DateTime latestAllowed([DateTime? asOf]) {
    final now = asOf ?? DateTime.now();
    final year = now.year - kMinimumProfileAgeYears;
    final candidate = DateTime(year, now.month, now.day);
    // 29 February: twenty-one years earlier is not a real date in a common
    // year, and DateTime rolls it forward to 1 March — which would admit
    // someone a day early. Clamp back to the last day of February instead.
    if (candidate.month != now.month) return DateTime(year, now.month + 1, 0);
    return candidate;
  }

  @override
  bool operator ==(Object other) =>
      other is BirthDateInput &&
      other.day == day &&
      other.month == month &&
      other.year == year;

  @override
  int get hashCode => Object.hash(day, month, year);
}

/// The outcome of applying the rule: exactly one of [date] and [error] is set.
class BirthDateResult {
  final DateTime? date;
  final BirthDateError? error;

  const BirthDateResult({this.date, this.error});
}

/// Whole years between [birthDate] and [asOf] (default: today), by complete
/// date — the number a profile displays.
///
/// The one age calculation in the app. Screens each used to carry their own
/// copy of this arithmetic, and every copy had to remember to decrement for a
/// birthday that has not come round yet.
int ageInYears(DateTime birthDate, [DateTime? asOf]) {
  final now = asOf ?? DateTime.now();
  var years = now.year - birthDate.year;
  if (now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day)) {
    years--;
  }
  return years;
}

/// A date of birth as the API carries it: `YYYY-MM-DD`, no time, no zone.
///
/// Matches `BasicDetailsDto.dob` on the server, which stores it into the
/// date-only `user_profiles.dob` column.
String birthDateToWire(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The inverse of [birthDateToWire], tolerant of the full ISO-8601 timestamps
/// older builds of this app wrote into the draft (`1998-08-15T00:00:00.000Z`,
/// and the zone-less `1998-08-15T00:00:00.000`).
///
/// Both are read for their **calendar-date fields as written**, never
/// converted: `1998-08-15T00:00:00.000Z` is the 15th of August whatever the
/// device's offset, and running it through a local-time conversion is exactly
/// how a birthdate loses a day.
DateTime? birthDateFromWire(dynamic value) {
  if (value is! String || value.trim().isEmpty) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value.trim());
  if (match == null) return null;
  final y = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  final d = int.parse(match.group(3)!);
  final parsed = DateTime(y, m, d);
  // A stored `2003-02-31` is not a date; refuse it rather than let DateTime
  // roll it into March.
  if (parsed.year != y || parsed.month != m || parsed.day != d) return null;
  return parsed;
}
