import {
  registerDecorator,
  ValidationArguments,
  ValidationOptions,
  ValidatorConstraint,
  ValidatorConstraintInterface,
} from 'class-validator';

/**
 * The date-of-birth rule, server side.
 *
 * The authority. The Flutter client applies the same table in
 * `Frontend/lib/core/utils/birth_date.dart` so a member is told what is wrong
 * before they submit, but nothing here trusts that: every value arriving on
 * `BasicDetailsDto.dob` is re-checked, and the write path
 * (`ProfileService.writeProfileFromDraft`) parses through {@link
 * parseBirthDate} rather than `new Date()`. Keep the two files in step.
 *
 * ## A date of birth is a calendar date
 *
 * It has no time of day and no timezone, and treating it as an instant is how
 * one drifts a day. `new Date('1998-08-15T00:00:00.000')` — the shape older
 * builds of the app sent — is parsed by JS as *local* midnight, so on a server
 * running IST it becomes `1998-08-14T18:30:00Z` and reads back as the 14th.
 *
 * So the whole file works in UTC calendar terms: a birthdate is stored as UTC
 * midnight of the day it names, and "today" is read off the UTC clock. That is
 * exactly what a `DATE` column would hold, it round-trips through
 * `toISOString()` unchanged, and it is what the client's `birthDateFromWire`
 * reads back.
 */

/** Youngest a member may be, in whole years. */
export const MINIMUM_PROFILE_AGE_YEARS = 21;

/**
 * There is deliberately **no maximum age and no earliest year**.
 *
 * An `EARLIEST_BIRTH_YEAR = 1950` floor briefly stood here, lifted from the
 * `firstDate: DateTime(1950)` bound of the calendar pickers the typed field
 * replaced. That bound was a picker's scroll range, not a product rule, and
 * promoting it to an API constraint invented a maximum age of 76 that nobody
 * had asked for — on a platform whose members include widowed and divorced
 * people remarrying later in life. It also broke existing members: anyone
 * already holding a pre-1950 `dob` would have had every subsequent
 * `PATCH /profiles/draft/basic-details` rejected, with no way to correct a
 * date that is simply true.
 *
 * The rules are exactly: a real calendar date, written as four-digit
 * `YYYY-MM-DD`, in the past, and at least MINIMUM_PROFILE_AGE_YEARS ago.
 * Adding an upper bound is a product decision and must be made explicitly.
 */

/** Why a date of birth was refused. */
export type BirthDateRejection =
  /** Not `YYYY-MM-DD` (nor a legacy ISO timestamp opening with one). */
  | 'MALFORMED'
  /** Three plausible numbers naming no real day — 2003-02-29, 2000-04-31. */
  | 'IMPOSSIBLE'
  /** A real date that has not happened yet. */
  | 'FUTURE'
  /** A real, past date, but under {@link MINIMUM_PROFILE_AGE_YEARS}. */
  | 'TOO_YOUNG';

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})(?:[T ].*)?$/;

/**
 * The calendar date [value] names, as UTC midnight, or null when it names
 * none.
 *
 * Accepts `YYYY-MM-DD` — what the client sends — and tolerates a full ISO-8601
 * timestamp opening with one, which is what builds of the app before this
 * change wrote into `draft_data` and what therefore still arrives from a
 * stored draft. Either way only the calendar-date fields **as written** are
 * read: `1998-08-15T00:00:00.000Z` and `1998-08-15T00:00:00.000` are both the
 * 15th of August, and no timezone conversion is applied to either.
 *
 * Rejects rollovers rather than accepting what `Date.UTC` would silently make
 * of them (`Date.UTC(2003, 1, 29)` is 1 March).
 */
export function parseBirthDate(value: unknown): Date | null {
  if (typeof value !== 'string') return null;
  const match = ISO_DATE.exec(value.trim());
  if (!match) return null;

  const [year, month, day] = [match[1], match[2], match[3]].map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  // Date.UTC maps years 0-99 onto 1900-1999, so `0050-01-01` would arrive as
  // 1950 and then fail the round-trip below as though it were an impossible
  // date. Dart's DateTime does not do this, and the two sides must agree on
  // what they accept.
  if (year < 100) parsed.setUTCFullYear(year);
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return null;
  }
  return parsed;
}

/**
 * The most recent date of birth the rule accepts: {@link
 * MINIMUM_PROFILE_AGE_YEARS} before [asOf], to the day, as UTC midnight.
 *
 * Someone born the day after this is a day short of the floor and is refused —
 * the whole reason the check compares complete dates rather than years.
 */
export function latestAllowedBirthDate(asOf: Date = new Date()): Date {
  const year = asOf.getUTCFullYear() - MINIMUM_PROFILE_AGE_YEARS;
  const month = asOf.getUTCMonth();
  const day = asOf.getUTCDate();
  const candidate = new Date(Date.UTC(year, month, day));
  // 29 February: twenty-one years earlier is not a date in a common year, and
  // Date.UTC rolls it forward to 1 March — which would admit someone a day
  // early. Clamp back to the last day of February instead.
  if (candidate.getUTCMonth() !== month) {
    return new Date(Date.UTC(year, month + 1, 0));
  }
  return candidate;
}

/** Today, as UTC midnight — the date half of [asOf]. */
function utcToday(asOf: Date): Date {
  return new Date(
    Date.UTC(asOf.getUTCFullYear(), asOf.getUTCMonth(), asOf.getUTCDate()),
  );
}

/**
 * Why [value] is not an acceptable date of birth, or null when it is.
 *
 * [asOf] defaults to now and exists so the age boundary is testable: a rule
 * that only misbehaves on one day of the year cannot be pinned against the
 * wall clock.
 */
export function birthDateRejection(
  value: unknown,
  asOf: Date = new Date(),
): BirthDateRejection | null {
  if (typeof value !== 'string' || !ISO_DATE.test(value.trim())) {
    return 'MALFORMED';
  }
  const parsed = parseBirthDate(value);
  if (!parsed) return 'IMPOSSIBLE';
  // Today included: nobody is born into the profile they are filling in.
  if (parsed.getTime() >= utcToday(asOf).getTime()) return 'FUTURE';
  if (parsed.getTime() > latestAllowedBirthDate(asOf).getTime()) {
    return 'TOO_YOUNG';
  }
  return null;
}

/** A parsed birth date as the wire and the client carry it: `YYYY-MM-DD`. */
export function birthDateToWire(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/**
 * [value] reduced to `YYYY-MM-DD`, or [value] untouched when it names no
 * calendar date.
 *
 * The compatibility seam. Older builds of the app send a full ISO-8601
 * timestamp (`1998-08-15T00:00:00.000Z`, the zone-less
 * `1998-08-15T00:00:00.000`, or an offset form such as
 * `1998-08-15T00:00:00+05:30`) and those builds are in members' hands, so the
 * API keeps accepting them. What it does **not** do is keep them: this runs as
 * a `@Transform` on the DTO, before validation, so the value that reaches the
 * validator, `draft_data` and every later reader is already date-only. A
 * timestamp therefore cannot linger in a draft to be re-parsed — possibly
 * differently — by something downstream.
 *
 * The time and the offset are discarded, never applied. `...T00:00:00+05:30`
 * is the 15th of August because that is the date written, and converting it to
 * UTC (the 14th, 18:30) would change a member's date of birth to settle a
 * question a birthdate does not ask. Discarding is also what makes the
 * mapping total: every accepted spelling of a given day maps to the same
 * `YYYY-MM-DD`, so no spelling can shift the date or slip past the age check.
 *
 * A value that is not a date is returned unchanged, so the validator — not the
 * transform — decides its fate and reports the reason.
 */
export function normalizeBirthDate(value: unknown): unknown {
  const parsed = parseBirthDate(value);
  return parsed ? birthDateToWire(parsed) : value;
}

/** Whether [value] is a date of birth the rule accepts. */
export function isBirthDate(value: unknown, asOf: Date = new Date()): boolean {
  return birthDateRejection(value, asOf) === null;
}

/**
 * What the 400 tells the client, per reason.
 *
 * Written as sentences a member can read, not as validator jargon, because
 * they are shown to one: `OnboardingStepScaffold` surfaces the message of a
 * 4xx `ApiException` verbatim rather than a generic "try again". Kept in step
 * with the client's own strings (`birthDateError*` in `app_en.arb`), which say
 * the same things for the same reasons — a member should not be able to tell
 * which side of the wire caught the mistake.
 */
const MESSAGES: Record<BirthDateRejection, string> = {
  MALFORMED: 'Please enter your date of birth as DD / MM / YYYY.',
  IMPOSSIBLE: 'Please enter a valid date of birth.',
  FUTURE: 'Date of birth cannot be in the future.',
  TOO_YOUNG: `You must be at least ${MINIMUM_PROFILE_AGE_YEARS} years old to register.`,
};

@ValidatorConstraint({ name: 'isBirthDate', async: false })
class BirthDateConstraint implements ValidatorConstraintInterface {
  validate(value: unknown): boolean {
    return isBirthDate(value);
  }

  defaultMessage(args: ValidationArguments): string {
    // Says which rule failed rather than "dob is invalid" — the client shows
    // this string when its own check has been bypassed (an older build, a raw
    // API call), and "invalid" gives the member nothing to act on.
    return MESSAGES[birthDateRejection(args.value) ?? 'MALFORMED'];
  }
}

/**
 * `@IsBirthDate()` — a calendar date in `YYYY-MM-DD` naming a real day, in the
 * past, and at least {@link MINIMUM_PROFILE_AGE_YEARS} ago. No upper bound;
 * see the note beside MINIMUM_PROFILE_AGE_YEARS.
 *
 * Replaces a bare `@IsDateString()`, which accepted every impossible, future
 * and under-age date the client had already been told to refuse.
 */
export function IsBirthDate(options?: ValidationOptions) {
  return function (object: object, propertyName: string): void {
    registerDecorator({
      target: object.constructor,
      propertyName,
      options,
      constraints: [],
      validator: BirthDateConstraint,
    });
  };
}
