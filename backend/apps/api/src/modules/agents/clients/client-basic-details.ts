/**
 * The basic details an agent enters for a client: step 1 of the member
 * registration (`ClientBasicDetails` in the agent contract). They become the
 * client's own registration draft when she accepts, so the rules are the
 * member wizard's: the same values, and the same date-of-birth rule
 * (`isBirthDate`: a real day, in the past, at least 21 years ago).
 *
 * Pure. A refusal names the fields, never their values.
 */
import { isBirthDate } from '../../profiles/validation/birth-date';
import type { ClientBasicDetails } from '../ports/agent-client-ports';

export const CLIENT_GENDERS = ['MALE', 'FEMALE'] as const;

export const CLIENT_MARITAL_STATUSES = [
  'NEVER_MARRIED',
  'DIVORCED',
  'WIDOWED',
  'AWAITING_DIVORCE',
] as const;

/** "Who is this profile for": the member app's values. */
export const CLIENT_PROFILE_CREATED_FOR = [
  'Myself',
  'Son',
  'Daughter',
  'Brother',
  'Sister',
  'Friend',
  'Relative',
] as const;

export const CLIENT_NAME_MAX_LENGTH = 50;

const FIELDS = [
  'firstName',
  'lastName',
  'gender',
  'dob',
  'maritalStatus',
  'profileCreatedFor',
] as const;

/** A calendar date only: the wizard's legacy timestamps are not accepted here. */
const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

export type ClientBasicDetailsCheck =
  { ok: true; details: ClientBasicDetails } | { ok: false; fields: string[] };

function name(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  const length = [...trimmed].length;
  return length >= 1 && length <= CLIENT_NAME_MAX_LENGTH ? trimmed : null;
}

function oneOf<T extends string>(
  value: unknown,
  allowed: readonly T[],
): T | null {
  return typeof value === 'string' &&
    (allowed as readonly string[]).includes(value)
    ? (value as T)
    : null;
}

/**
 * Checks and normalises (trims the names) the details. `now` is the day the
 * age is judged on. Fields are reported as `details.<field>`; an extra
 * property is reported as `details` (its name came from the caller).
 */
export function validateClientBasicDetails(
  input: unknown,
  now: Date,
): ClientBasicDetailsCheck {
  if (typeof input !== 'object' || input === null || Array.isArray(input)) {
    return { ok: false, fields: ['details'] };
  }
  const raw = input as Record<string, unknown>;
  const fields: string[] = [];
  if (
    Object.keys(raw).some((key) => !(FIELDS as readonly string[]).includes(key))
  ) {
    fields.push('details');
  }

  const firstName = name(raw.firstName);
  const lastName = name(raw.lastName);
  const gender = oneOf(raw.gender, CLIENT_GENDERS);
  const dob =
    typeof raw.dob === 'string' &&
    DATE_ONLY.test(raw.dob) &&
    isBirthDate(raw.dob, now)
      ? raw.dob
      : null;
  const maritalStatus = oneOf(raw.maritalStatus, CLIENT_MARITAL_STATUSES);
  const profileCreatedFor = oneOf(
    raw.profileCreatedFor,
    CLIENT_PROFILE_CREATED_FOR,
  );

  if (firstName === null) fields.push('details.firstName');
  if (lastName === null) fields.push('details.lastName');
  if (gender === null) fields.push('details.gender');
  if (dob === null) fields.push('details.dob');
  if (maritalStatus === null) fields.push('details.maritalStatus');
  if (profileCreatedFor === null) fields.push('details.profileCreatedFor');

  if (
    fields.length > 0 ||
    firstName === null ||
    lastName === null ||
    gender === null ||
    dob === null ||
    maritalStatus === null ||
    profileCreatedFor === null
  ) {
    return { ok: false, fields };
  }
  return {
    ok: true,
    details: {
      firstName,
      lastName,
      gender,
      dob,
      maritalStatus,
      profileCreatedFor,
    },
  };
}

/**
 * Reads details back from their sealed JSON (already opened). Throws on
 * anything that is not what `validateClientBasicDetails` stored: that is
 * corrupt data, not a client mistake.
 */
export function parseStoredClientBasicDetails(
  json: string,
): ClientBasicDetails {
  const parsed = JSON.parse(json) as unknown;
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    throw new TypeError('Stored client details are not an object.');
  }
  const raw = parsed as Record<string, unknown>;
  for (const field of FIELDS) {
    if (typeof raw[field] !== 'string') {
      throw new TypeError('Stored client details are incomplete.');
    }
  }
  return {
    firstName: raw.firstName as string,
    lastName: raw.lastName as string,
    gender: raw.gender as ClientBasicDetails['gender'],
    dob: raw.dob as string,
    maritalStatus: raw.maritalStatus as ClientBasicDetails['maritalStatus'],
    profileCreatedFor:
      raw.profileCreatedFor as ClientBasicDetails['profileCreatedFor'],
  };
}
