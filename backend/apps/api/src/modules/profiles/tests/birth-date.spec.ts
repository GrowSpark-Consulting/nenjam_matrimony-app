import { validate } from 'class-validator';
import { plainToInstance } from 'class-transformer';
import { BasicDetailsDto } from '../dto/basic-details.dto';
import {
  birthDateRejection,
  isBirthDate,
  latestAllowedBirthDate,
  MINIMUM_PROFILE_AGE_YEARS,
  normalizeBirthDate,
  parseBirthDate,
} from '../validation/birth-date';

/**
 * The date-of-birth rule the API enforces, and the DTO that applies it.
 *
 * The client applies the same table in `Frontend/lib/core/utils/birth_date.dart`
 * and `Frontend/test/core/utils/birth_date_test.dart` asserts it there; this is
 * the half that has to hold when the client is an older build, a raw curl, or
 * lying.
 */
describe('parseBirthDate', () => {
  it('reads a date-only string as UTC midnight of that day', () => {
    const parsed = parseBirthDate('1998-08-15');
    expect(parsed?.toISOString()).toBe('1998-08-15T00:00:00.000Z');
  });

  it(
    'reads a stored ISO timestamp for the day it names, not the day its ' +
      'offset lands on',
    () => {
      // Both shapes older builds of the app wrote into `draft_data`. The
      // zone-less one is the bug this replaced: `new Date(...)` parsed it as
      // LOCAL midnight, so an IST server stored — and read back — the 14th.
      expect(parseBirthDate('1998-08-15T00:00:00.000Z')?.toISOString()).toBe(
        '1998-08-15T00:00:00.000Z',
      );
      expect(parseBirthDate('1998-08-15T00:00:00.000')?.toISOString()).toBe(
        '1998-08-15T00:00:00.000Z',
      );
    },
  );

  it('accepts 29 February of a leap year', () => {
    expect(parseBirthDate('2004-02-29')?.toISOString()).toBe(
      '2004-02-29T00:00:00.000Z',
    );
  });

  it('refuses a day the month does not have rather than rolling it over', () => {
    // Date.UTC(2003, 1, 29) is 1 March; storing that would silently change
    // someone's date of birth.
    expect(parseBirthDate('2003-02-29')).toBeNull();
    expect(parseBirthDate('1998-02-31')).toBeNull();
    expect(parseBirthDate('2000-04-31')).toBeNull();
    expect(parseBirthDate('1998-13-15')).toBeNull();
    expect(parseBirthDate('1998-08-00')).toBeNull();
  });

  it('refuses anything that is not a calendar date', () => {
    expect(parseBirthDate('15/08/1998')).toBeNull();
    expect(parseBirthDate('1998-8-5')).toBeNull();
    expect(parseBirthDate('')).toBeNull();
    expect(parseBirthDate(undefined)).toBeNull();
    expect(parseBirthDate(null)).toBeNull();
    expect(parseBirthDate(19980815)).toBeNull();
    expect(parseBirthDate({ dob: '1998-08-15' })).toBeNull();
  });
});

describe('birthDateRejection', () => {
  // Pinned rather than read off the wall clock: an age boundary that only
  // misbehaves on one day of the year is not testable otherwise.
  const today = new Date('2026-09-08T00:00:00.000Z');

  it('accepts an ordinary date of birth', () => {
    expect(birthDateRejection('1998-08-15', today)).toBeNull();
    expect(isBirthDate('1998-08-15', today)).toBe(true);
  });

  it('accepts someone who turns 21 today', () => {
    expect(birthDateRejection('2005-09-08', today)).toBeNull();
  });

  it('refuses someone who turns 21 tomorrow', () => {
    // The case a `getFullYear() - birthYear >= 21` check gets wrong: the year
    // difference is 21 and the birthday has not happened.
    expect(2026 - 2005).toBe(MINIMUM_PROFILE_AGE_YEARS);
    expect(birthDateRejection('2005-09-09', today)).toBe('TOO_YOUNG');
    expect(birthDateRejection('2005-12-31', today)).toBe('TOO_YOUNG');
  });

  it('accepts a birthday already past this year', () => {
    expect(birthDateRejection('2005-01-01', today)).toBeNull();
    expect(birthDateRejection('2005-09-07', today)).toBeNull();
  });

  it('refuses today and every date after it', () => {
    expect(birthDateRejection('2026-09-08', today)).toBe('FUTURE');
    expect(birthDateRejection('2026-09-09', today)).toBe('FUTURE');
    expect(birthDateRejection('2027-08-15', today)).toBe('FUTURE');
  });

  it('has no maximum age', () => {
    // There is no upper bound and no earliest year. A 1950 floor briefly
    // stood here, lifted from the old calendar picker's scroll range; it
    // invented a maximum age of 76 nobody asked for and would have rejected
    // every future PATCH from an existing member already holding a pre-1950
    // date. Only the minimum-age rule applies.
    expect(birthDateRejection('1949-12-31', today)).toBeNull();
    expect(birthDateRejection('1900-08-15', today)).toBeNull();
    expect(birthDateRejection('1900-01-01', today)).toBeNull();
  });

  it('does not read a two-digit-looking year as the 1900s', () => {
    // Date.UTC(50, 0, 1) is 1950 — which, unguarded, would make `0050-01-01`
    // fail the round-trip check and be reported as an impossible date, while
    // Dart's DateTime accepts it. The two sides have to agree.
    expect(parseBirthDate('0050-01-01')?.getUTCFullYear()).toBe(50);
    expect(birthDateRejection('0050-01-01', today)).toBeNull();
  });

  it('tells a malformed date apart from an impossible one', () => {
    expect(birthDateRejection('not-a-date', today)).toBe('MALFORMED');
    expect(birthDateRejection(undefined, today)).toBe('MALFORMED');
    expect(birthDateRejection('2003-02-29', today)).toBe('IMPOSSIBLE');
  });

  it('reads "today" off the UTC clock, not the server timezone', () => {
    // The rule must not move because the box it runs on moved. Every accessor
    // in birth-date.ts is a getUTC* one, so the same instant yields the same
    // boundary whatever TZ the process was started with — and two instants on
    // the same UTC day yield the same boundary regardless of where in that day
    // they fall.
    const earlyUtc = new Date('2026-09-08T00:30:00.000Z');
    const lateUtc = new Date('2026-09-08T23:30:00.000Z');
    expect(latestAllowedBirthDate(earlyUtc).toISOString()).toBe(
      '2005-09-08T00:00:00.000Z',
    );
    expect(latestAllowedBirthDate(lateUtc).toISOString()).toBe(
      latestAllowedBirthDate(earlyUtc).toISOString(),
    );
    expect(birthDateRejection('2005-09-08', earlyUtc)).toBeNull();
    expect(birthDateRejection('2005-09-08', lateUtc)).toBeNull();
    expect(birthDateRejection('2005-09-09', lateUtc)).toBe('TOO_YOUNG');
  });

  it('crosses the boundary only when the UTC day does', () => {
    // 23:30 UTC on the 8th is already the 9th in IST. The rule stays on the
    // 8th, which is the strict side: the API is the authority and refusing a
    // few hours early is safe, where accepting early is not.
    const beforeMidnightUtc = new Date('2026-09-08T23:59:59.999Z');
    const afterMidnightUtc = new Date('2026-09-09T00:00:00.000Z');
    expect(birthDateRejection('2005-09-09', beforeMidnightUtc)).toBe(
      'TOO_YOUNG',
    );
    expect(birthDateRejection('2005-09-09', afterMidnightUtc)).toBeNull();
  });

  it('clamps the floor back on 29 February rather than a day forward', () => {
    const leapDay = new Date('2028-02-29T00:00:00.000Z');
    expect(latestAllowedBirthDate(leapDay).toISOString()).toBe(
      '2007-02-28T00:00:00.000Z',
    );
    // Otherwise Date.UTC would roll to 1 March and admit this a day early.
    expect(birthDateRejection('2007-03-01', leapDay)).toBe('TOO_YOUNG');
  });
});

/**
 * The compatibility seam, exhaustively: every spelling of a day an older build
 * can send must reduce to the same `YYYY-MM-DD`, so none of them can shift the
 * calendar date or slip past the age check.
 */
describe('normalizeBirthDate', () => {
  it.each([
    ['already date-only', '1998-08-15'],
    ['UTC timestamp', '1998-08-15T00:00:00.000Z'],
    ['zone-less timestamp', '1998-08-15T00:00:00.000'],
    ['positive-offset timestamp', '1998-08-15T00:00:00+05:30'],
    ['negative-offset timestamp', '1998-08-15T00:00:00-08:00'],
    ['late in the day, +05:30', '1998-08-15T23:59:59.999+05:30'],
    ['early in the day, -08:00', '1998-08-15T00:00:01.000-08:00'],
    ['space separator', '1998-08-15 12:34:56'],
    ['surrounding whitespace', '  1998-08-15T00:00:00.000Z  '],
  ])('reduces %s to the day it names', (_label, value) => {
    expect(normalizeBirthDate(value)).toBe('1998-08-15');
    // And the parse agrees, so validation and the write see the same day.
    expect(parseBirthDate(value)?.toISOString()).toBe(
      '1998-08-15T00:00:00.000Z',
    );
  });

  it('never moves the date across midnight, whichever way the offset leans', () => {
    // `1998-08-15T00:00:00+05:30` is 1998-08-14T18:30Z as an instant. Applying
    // the offset would hand the member a birthday one day earlier; the date
    // written is the answer, so the offset is discarded.
    expect(new Date('1998-08-15T00:00:00+05:30').getUTCDate()).toBe(14);
    expect(normalizeBirthDate('1998-08-15T00:00:00+05:30')).toBe('1998-08-15');
  });

  it('leaves a non-date alone for the validator to report', () => {
    expect(normalizeBirthDate('15/08/1998')).toBe('15/08/1998');
    expect(normalizeBirthDate('2003-02-29')).toBe('2003-02-29');
    expect(normalizeBirthDate(undefined)).toBeUndefined();
    expect(normalizeBirthDate(19980815)).toBe(19980815);
  });

  it('is idempotent', () => {
    const once = normalizeBirthDate('1998-08-15T00:00:00+05:30');
    expect(normalizeBirthDate(once)).toBe(once);
  });
});

describe('BasicDetailsDto', () => {
  const errorsFor = async (dob?: unknown) => {
    const dto = plainToInstance(BasicDetailsDto, {
      firstName: 'Arjun',
      lastName: 'Krishnan',
      gender: 'MALE',
      maritalStatus: 'NEVER_MARRIED',
      profileCreatedFor: 'Myself',
      ...(dob === undefined ? {} : { dob }),
    });
    return validate(dto);
  };

  const dobErrors = async (dob?: unknown) =>
    (await errorsFor(dob)).filter((e) => e.property === 'dob');

  it('accepts a valid date of birth', async () => {
    expect(await dobErrors('1998-08-15')).toHaveLength(0);
  });

  it('accepts the step being saved without one', async () => {
    // Every field on this DTO is optional — the wizard PATCHes a section at a
    // time and a member may not have reached the date yet. Absence is not the
    // same as a bad value, and finalize() is what refuses to complete a
    // profile that never supplied one.
    expect(await dobErrors(undefined)).toHaveLength(0);
  });

  it('refuses an impossible date', async () => {
    const [error] = await dobErrors('2003-02-29');
    expect(error?.constraints?.isBirthDate).toBe(
      'Please enter a valid date of birth.',
    );
  });

  it('refuses a malformed date', async () => {
    expect((await dobErrors('15/08/1998'))[0]?.constraints?.isBirthDate).toBe(
      'Please enter your date of birth as DD / MM / YYYY.',
    );
    expect((await dobErrors(19980815))[0]?.constraints?.isBirthDate).toBe(
      'Please enter your date of birth as DD / MM / YYYY.',
    );
  });

  it('refuses a future date', async () => {
    const nextYear = new Date().getUTCFullYear() + 1;
    expect(
      (await dobErrors(`${nextYear}-08-15`))[0]?.constraints?.isBirthDate,
    ).toBe('Date of birth cannot be in the future.');
  });

  it('refuses someone under 21, and says so in the message', async () => {
    const tenYearsAgo = new Date().getUTCFullYear() - 10;
    const [error] = await dobErrors(`${tenYearsAgo}-08-15`);
    expect(error?.constraints?.isBirthDate).toBe(
      'You must be at least 21 years old to register.',
    );
  });

  it('accepts someone who turned 21 today', async () => {
    const now = new Date();
    const boundary = latestAllowedBirthDate(now).toISOString().slice(0, 10);
    expect(await dobErrors(boundary)).toHaveLength(0);
  });

  it('refuses the day after that boundary', async () => {
    const now = new Date();
    const tooYoung = new Date(latestAllowedBirthDate(now));
    tooYoung.setUTCDate(tooYoung.getUTCDate() + 1);
    expect(await dobErrors(tooYoung.toISOString().slice(0, 10))).toHaveLength(
      1,
    );
  });

  it('still accepts the ISO timestamps older builds send', async () => {
    // Those builds are in members' hands and their drafts hold this shape;
    // refusing it would break the signup flow for everyone who has not
    // updated.
    expect(await dobErrors('1998-08-15T00:00:00.000Z')).toHaveLength(0);
  });

  it('stores the normalised date, not the timestamp it was sent', async () => {
    // The value that reaches `draft_data` — @Transform runs during
    // plainToInstance, before validation, exactly as the global
    // ValidationPipe (transform: true) applies it.
    const dto = plainToInstance(BasicDetailsDto, {
      dob: '1998-08-15T00:00:00+05:30',
    });
    expect(dto.dob).toBe('1998-08-15');
    expect(await validate(dto)).toHaveLength(0);
  });

  it.each([
    ['a UTC timestamp', 'Z'],
    ['a positive-offset timestamp', '+05:30'],
    ['a negative-offset timestamp', '-08:00'],
    ['a zone-less timestamp', ''],
  ])('cannot use %s to slip past the age floor', async (_label, suffix) => {
    const now = new Date();
    // One day under 21, spelled as a timestamp. Whatever the offset, the day
    // written is the day judged, so every spelling is refused.
    const tooYoung = new Date(latestAllowedBirthDate(now));
    tooYoung.setUTCDate(tooYoung.getUTCDate() + 1);
    const day = tooYoung.toISOString().slice(0, 10);

    const errors = await dobErrors(`${day}T00:00:00.000${suffix}`);
    expect(errors).toHaveLength(1);
    expect(errors[0]?.constraints?.isBirthDate).toBe(
      'You must be at least 21 years old to register.',
    );
  });

  it.each([
    ['a UTC timestamp', 'Z'],
    ['a positive-offset timestamp', '+05:30'],
    ['a negative-offset timestamp', '-08:00'],
  ])('accepts exactly 21 spelled as %s', async (_label, suffix) => {
    const day = latestAllowedBirthDate(new Date()).toISOString().slice(0, 10);
    expect(await dobErrors(`${day}T00:00:00.000${suffix}`)).toHaveLength(0);
  });

  it('refuses an impossible date spelled as a timestamp', async () => {
    expect(
      (await dobErrors('2003-02-29T00:00:00.000Z'))[0]?.constraints
        ?.isBirthDate,
    ).toBe('Please enter a valid date of birth.');
  });

  it('refuses a future date spelled as a timestamp', async () => {
    const nextYear = new Date().getUTCFullYear() + 1;
    expect(
      (await dobErrors(`${nextYear}-08-15T00:00:00.000+05:30`))[0]?.constraints
        ?.isBirthDate,
    ).toBe('Date of birth cannot be in the future.');
  });

  it('has no maximum age', async () => {
    expect(await dobErrors('1940-08-15')).toHaveLength(0);
    expect(await dobErrors('1900-01-01')).toHaveLength(0);
  });

  it('does not touch the rest of the section', async () => {
    // The one field this change alters. A bad date must not fail gender, and
    // a bad gender must still fail.
    expect(await errorsFor('1998-08-15')).toHaveLength(0);
    const dto = plainToInstance(BasicDetailsDto, {
      gender: 'OTHER',
      dob: '1998-08-15',
    });
    const errors = await validate(dto);
    expect(errors.map((e) => e.property)).toEqual(['gender']);
  });
});
