import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/utils/birth_date.dart';

/// The date-of-birth rule, on its own.
///
/// Every screen that asks for a date of birth and every gate that asks
/// whether one has been given goes through [BirthDateInput], and the server
/// applies the same table in
/// `backend/apps/api/src/modules/profiles/validation/birth-date.ts`. This is
/// where the table itself is asserted; the screen tests only check that the
/// screen consults it.
void main() {
  BirthDateInput input(String d, String m, String y) =>
      BirthDateInput(day: d, month: m, year: y);

  group('accepts', () {
    test('an ordinary date', () {
      expect(input('15', '08', '1998').date, DateTime(1998, 8, 15));
      expect(input('15', '08', '1998').error, isNull);
    });

    test('single-digit parts, as typed', () {
      expect(input('5', '2', '1998').date, DateTime(1998, 2, 5));
    });

    test('29 February of a leap year', () {
      expect(input('29', '02', '2004').date, DateTime(2004, 2, 29));
    });

    test('a date of birth with no upper bound on age', () {
      // There is no maximum age and no earliest year. A 1950 floor briefly
      // stood here, inherited from the old calendar picker's scroll range; it
      // invented a maximum age of 76 and would have locked an existing member
      // holding a pre-1950 date out of saving their own profile.
      expect(input('01', '01', '1950').date, DateTime(1950, 1, 1));
      expect(input('15', '08', '1900').date, DateTime(1900, 8, 15));
      expect(input('31', '12', '1949').error, isNull);
    });
  });

  group('rejects', () {
    test('a day outside 1-31', () {
      expect(input('00', '08', '1998').error, BirthDateError.day);
      expect(input('32', '08', '1998').error, BirthDateError.day);
      expect(input('', '08', '1998').error, BirthDateError.day);
    });

    test('a month outside 1-12', () {
      expect(input('15', '13', '1998').error, BirthDateError.month);
      expect(input('15', '00', '1998').error, BirthDateError.month);
      expect(input('15', '', '1998').error, BirthDateError.month);
    });

    test('a year that is not four digits', () {
      expect(input('15', '08', '98').error, BirthDateError.year);
      expect(input('15', '08', '199').error, BirthDateError.year);
      expect(input('15', '08', '').error, BirthDateError.year);
    });

    test('a day that month does not have', () {
      // The three cases DateTime silently rolls over into the next month.
      expect(input('31', '02', '1998').error, BirthDateError.invalidDate);
      expect(input('31', '04', '2000').error, BirthDateError.invalidDate);
      expect(input('29', '02', '2003').error, BirthDateError.invalidDate);
    });

    test('anything but digits', () {
      expect(input('1a', '08', '1998').error, BirthDateError.day);
      expect(input('15', '-8', '1998').error, BirthDateError.month);
      expect(input('15', '08', '19x8').error, BirthDateError.year);
    });
  });

  // The rule that has to compare complete dates, not years. Pinned against a
  // fixed "today" — an age boundary that only misbehaves on one day of the
  // year is not testable against the wall clock.
  group('the age floor, against 8 September 2026', () {
    final today = DateTime(2026, 9, 8);

    test('exactly 21 today is accepted', () {
      final result = input('08', '09', '2005').evaluateAsOf(today);
      expect(result.date, DateTime(2005, 9, 8));
      expect(result.error, isNull);
    });

    test('21 tomorrow is not', () {
      // The case a `currentYear - birthYear >= 21` test gets wrong: the years
      // differ by 21, and the birthday has not happened.
      expect(
        input('09', '09', '2005').evaluateAsOf(today).error,
        BirthDateError.tooYoung,
      );
      expect(2026 - 2005, 21, reason: 'the year difference alone says 21');
    });

    test('a day older than the floor is accepted', () {
      expect(input('07', '09', '2005').evaluateAsOf(today).error, isNull);
    });

    test('a birthday earlier this year is accepted', () {
      expect(input('01', '01', '2005').evaluateAsOf(today).error, isNull);
    });

    test('a birthday later this year is not', () {
      expect(
        input('31', '12', '2005').evaluateAsOf(today).error,
        BirthDateError.tooYoung,
      );
    });

    test('today itself is a future date, not an age failure', () {
      expect(
        input('08', '09', '2026').evaluateAsOf(today).error,
        BirthDateError.future,
      );
    });

    test('tomorrow is rejected as a future date', () {
      expect(
        input('09', '09', '2026').evaluateAsOf(today).error,
        BirthDateError.future,
      );
      expect(
        input('15', '08', '2027').evaluateAsOf(today).error,
        BirthDateError.future,
      );
    });

    test('latestAllowed is exactly 21 years back to the day', () {
      expect(BirthDateInput.latestAllowed(today), DateTime(2005, 9, 8));
    });
  });

  test('29 February clamps the floor back rather than a day forward', () {
    // 29 Feb 2028 minus 21 years is not a date in 2007, and DateTime would
    // roll it to 1 March — which would let someone born on 1 March 2007
    // register a day early.
    expect(
      BirthDateInput.latestAllowed(DateTime(2028, 2, 29)),
      DateTime(2007, 2, 28),
    );
    expect(
      input('01', '03', '2007').evaluateAsOf(DateTime(2028, 2, 29)).error,
      BirthDateError.tooYoung,
    );
  });

  group('liveError stays quiet mid-entry', () {
    test('on an untouched form', () {
      expect(const BirthDateInput().liveError, isNull);
    });

    test('on a part still being typed', () {
      // "1" is on its way to 15; "199" to 1998.
      expect(input('1', '', '').liveError, isNull);
      expect(input('15', '0', '').liveError, isNull);
      expect(input('15', '08', '199').liveError, isNull);
    });

    test('but speaks as soon as a full part is wrong', () {
      expect(input('32', '', '').liveError, BirthDateError.day);
      expect(input('15', '13', '').liveError, BirthDateError.month);
    });

    test('and holds whole-date complaints until all three are full', () {
      expect(input('31', '02', '200').liveError, isNull);
      expect(input('31', '02', '2003').liveError, BirthDateError.invalidDate);
    });
  });

  group('calendarDate ignores the age floor', () {
    // The question routing asks — "has this been answered?" — as against
    // "may this be submitted?". A member who registered when the floor was 18
    // has a real date of birth and no way to change it; treating it as
    // unanswered would send them back to the step forever.
    test('a real date under the floor is still a date', () {
      final under21 = input('15', '08', '${DateTime.now().year - 19}');
      expect(under21.date, isNull);
      expect(under21.error, BirthDateError.tooYoung);
      expect(under21.calendarDate, isNotNull);
    });

    test('but an impossible, future or pre-1950 date is still not one', () {
      expect(input('31', '02', '2003').calendarDate, isNull);
      expect(input('15', '08', '${DateTime.now().year + 1}').calendarDate,
          isNull);
      expect(input('15', '08', '199').calendarDate, isNull);
      expect(const BirthDateInput().calendarDate, isNull);
    });

    test('and an ordinary date is unaffected', () {
      expect(input('15', '08', '1998').calendarDate, DateTime(1998, 8, 15));
    });
  });

  group('fromDate', () {
    test('zero-pads a stored date the way a member types it', () {
      final restored = BirthDateInput.fromDate(DateTime(1995, 3, 21));
      expect(restored.day, '21');
      expect(restored.month, '03');
      expect(restored.year, '1995');
      expect(restored.date, DateTime(1995, 3, 21));
    });

    test('is empty and untouched for no date', () {
      expect(BirthDateInput.fromDate(null), const BirthDateInput());
      expect(BirthDateInput.fromDate(null).isTouched, isFalse);
    });
  });

  group('ageInYears', () {
    test('counts whole years by complete date', () {
      expect(ageInYears(DateTime(2005, 9, 8), DateTime(2026, 9, 8)), 21);
      expect(ageInYears(DateTime(2005, 9, 9), DateTime(2026, 9, 8)), 20);
      expect(ageInYears(DateTime(2005, 12, 31), DateTime(2026, 9, 8)), 20);
    });
  });

  group('the wire form', () {
    test('is date-only, zero-padded', () {
      expect(birthDateToWire(DateTime(1998, 8, 15)), '1998-08-15');
      expect(birthDateToWire(DateTime(2004, 2, 29)), '2004-02-29');
    });

    test('round-trips', () {
      expect(
        birthDateFromWire(birthDateToWire(DateTime(1998, 8, 15))),
        DateTime(1998, 8, 15),
      );
    });

    test('reads a stored date for the day it names, whatever the zone', () {
      // Every shape an older build of the app, or a draft saved by one, can
      // present. All of them are the 15th of August: the date written is the
      // answer, and applying an offset or a local-time conversion to it is
      // exactly how a birthdate loses a day. Mirrors normalizeBirthDate on
      // the server, which reduces the same set to '1998-08-15'.
      for (final value in [
        '1998-08-15',
        '1998-08-15T00:00:00.000Z',
        '1998-08-15T00:00:00.000',
        '1998-08-15T00:00:00+05:30',
        '1998-08-15T00:00:00-08:00',
        '1998-08-15T23:59:59.999+05:30',
        '1998-08-15 12:34:56',
        '  1998-08-15T00:00:00.000Z  ',
      ]) {
        expect(birthDateFromWire(value), DateTime(1998, 8, 15), reason: value);
        expect(birthDateToWire(birthDateFromWire(value)!), '1998-08-15');
      }
    });

    test('does not move the date across midnight for an offset form', () {
      // As an instant, 1998-08-15T00:00:00+05:30 is the 14th in UTC. Reading
      // it that way would hand the member a birthday a day earlier than the
      // one they gave.
      expect(DateTime.parse('1998-08-15T00:00:00+05:30').toUtc().day, 14);
      expect(birthDateFromWire('1998-08-15T00:00:00+05:30')!.day, 15);
    });

    test('drops anything that is not a date', () {
      expect(birthDateFromWire(null), isNull);
      expect(birthDateFromWire(''), isNull);
      expect(birthDateFromWire(19980815), isNull);
      expect(birthDateFromWire('15/08/1998'), isNull);
      // A stored 31 February is not a date; it must not roll into March.
      expect(birthDateFromWire('2003-02-31'), isNull);
    });
  });
}
