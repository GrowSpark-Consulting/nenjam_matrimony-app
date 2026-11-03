/**
 * The profile an agent fills in for a client (plan section 7.1 and the
 * partner preferences): the member wizard's own sections and field names
 * (`registration_steps.draft_data`), so a profile created through Way 2 is
 * exactly what a member who typed it would have.
 *
 * - Every field is optional while the draft is being edited; the fields the
 *   agent must fill before SUBMIT are the one list in
 *   `client-profile-required.ts`.
 * - Allowed values are the wizard's: the closed lists it offers (copied from
 *   Frontend/lib/core/constants/profile_options.dart, step_family.dart,
 *   step_horoscope.dart and partner_preference_labels.dart, value for value),
 *   free text where it lets the member type, and master-data CODES for
 *   religion, community, country, state and city (checked against the
 *   reference data by the service; the labels are filled in from it, as the
 *   wizard stores both).
 * - "Who is this profile for" is not asked: a Way 2 profile is always the
 *   client's own (`profileCreatedFor: 'Myself'`, written at accept).
 *
 * Pure. A refusal names the fields (`details.<section>.<field>`), never their
 * values; an unknown key is reported as its section (its name came from the
 * caller).
 */
import { isBirthDate } from '../../profiles/validation/birth-date';
import { CLIENT_PROFILE_REQUIRED_AT_SUBMIT } from './client-profile-required';

// --- The wizard's allowed values --------------------------------------------

export const CLIENT_GENDERS = ['MALE', 'FEMALE'] as const;
export const CLIENT_MARITAL_STATUSES = [
  'NEVER_MARRIED',
  'DIVORCED',
  'WIDOWED',
  'AWAITING_DIVORCE',
] as const;

/** The wizard's height labels: `5'9" (175 cm)`, 122 to 213 cm. */
export function clientHeightLabel(cm: number): string {
  const totalInches = Math.round(cm / 2.54);
  return `${Math.floor(totalInches / 12)}'${totalInches % 12}" (${cm} cm)`;
}
export const CLIENT_HEIGHTS: readonly string[] = Array.from(
  { length: 213 - 122 + 1 },
  (_, i) => clientHeightLabel(122 + i),
);

export const CLIENT_DIETS = [
  'Vegetarian',
  'Non-Vegetarian',
  'Eggetarian',
  'Vegan',
  'Jain',
] as const;
export const CLIENT_EMPLOYMENT_TYPES = [
  'Private',
  'Government',
  'Business',
  'Self-Employed',
  'Not Working',
  'Student',
  'Retired',
] as const;
export const CLIENT_INCOME_RANGES = [
  'Below 5 Lakhs',
  '5 - 10 Lakhs',
  '10 - 20 Lakhs',
  '20 - 50 Lakhs',
  '50 Lakhs - 1 Crore',
  '1 Crore+',
] as const;
export const CLIENT_FAMILY_TYPES = ['Joint Family', 'Nuclear Family'] as const;
export const CLIENT_SIBLING_RELATIONS = ['BROTHER', 'SISTER'] as const;
export const CLIENT_RASHIS = [
  'Mesha',
  'Vrishabha',
  'Mithuna',
  'Kataka',
  'Simha',
  'Kanya',
  'Tula',
  'Vrischika',
  'Dhanu',
  'Makara',
  'Kumbha',
  'Meena',
  "Don't Know",
] as const;
export const CLIENT_STARS = [
  'Aswini',
  'Bharani',
  'Karthigai',
  'Rohini',
  'Mrigasheersham',
  'Thiruvaathirai',
  'Punarpoosam',
  'Poosam',
  'Aayilyam',
  'Magam',
  'Pooram',
  'Uthiram',
  'Hastham',
  'Chithirai',
  'Swaathi',
  'Visaagam',
  'Anusham',
  'Kettai',
  'Moolam',
  'Pooraadam',
  'Uthiraadam',
  'Thiruvonam',
  'Avittam',
  'Sadhayam',
  'Poorattathi',
  'Uthirattathi',
  'Revathi',
  "Don't Know",
] as const;

// Partner preferences: the wizard's step 10 / Partner Preferences page lists.
export const CLIENT_PREF_AGE_RANGES = [
  '18-22',
  '22-26',
  '26-30',
  '30-35',
  '35-40',
  '40-50',
  'Any',
] as const;
export const CLIENT_PREF_HEIGHT_RANGES = [
  `4'6"-5'0"`,
  `5'0"-5'4"`,
  `5'4"-5'8"`,
  `5'8"-6'0"`,
  `6'0"+`,
  'Any',
] as const;
export const CLIENT_PREF_MARITAL_STATUSES = [
  'Never Married',
  "Doesn't Matter",
  'Any',
] as const;
export const CLIENT_PREF_RELIGIONS = [
  'Hindu',
  'Christian',
  'Muslim',
  'Jain',
  'Sikh',
  'Any',
] as const;
export const CLIENT_PREF_CASTES = [
  'Same Caste',
  'Any Caste',
  'Inter-Caste OK',
] as const;
export const CLIENT_PREF_OCCUPATIONS = [
  'Software / IT',
  'Doctor',
  'Government',
  'Business',
  'Any',
] as const;
export const CLIENT_PREF_INCOMES = [
  '5-10 Lakhs',
  '10-20 Lakhs',
  '20-50 Lakhs',
  '50 Lakhs+',
  'Any',
] as const;
export const CLIENT_PREF_LOCATIONS = [
  'Same City',
  'Same State',
  'Anywhere in India',
  'NRI OK',
  'Any',
] as const;
export const CLIENT_PREF_MIN_EDUCATIONS = [
  'High School',
  'Bachelors',
  'Masters',
  'Doctorate',
  'Any',
] as const;
export const CLIENT_PREF_DIETS = [
  'Vegetarian',
  'Eggetarian',
  'Vegan',
  'Non-Vegetarian',
  "Doesn't Matter",
] as const;

// --- The field table ----------------------------------------------------------

type Rule =
  | { kind: 'name' }
  | { kind: 'text'; max: number }
  | { kind: 'oneOf'; values: readonly string[] }
  | { kind: 'dob' }
  | { kind: 'code' }
  | { kind: 'int'; min: number; max: number };

type SectionRules = Record<string, Rule | Record<string, Rule>>;

const name: Rule = { kind: 'name' };
const text = (max: number): Rule => ({ kind: 'text', max });
const oneOf = (values: readonly string[]): Rule => ({ kind: 'oneOf', values });
const code: Rule = { kind: 'code' };

/** Every field an agent may fill, by wizard section. Siblings are special (a list). */
export const CLIENT_PROFILE_FIELDS = {
  basicDetails: {
    firstName: name,
    lastName: name,
    gender: oneOf(CLIENT_GENDERS),
    dob: { kind: 'dob' },
    maritalStatus: oneOf(CLIENT_MARITAL_STATUSES),
  },
  religionDetails: {
    religionCode: code,
    communityCode: code,
    subCaste: text(50),
  },
  languageDetails: { motherTongue: text(50) },
  locationDetails: {
    countryCode: code,
    stateCode: code,
    cityCode: code,
    nativePlace: text(100),
  },
  educationDetails: {
    qualification: text(100),
    occupation: text(100),
    employmentType: oneOf(CLIENT_EMPLOYMENT_TYPES),
    annualIncome: oneOf(CLIENT_INCOME_RANGES),
  },
  physicalDetails: { height: oneOf(CLIENT_HEIGHTS) },
  lifestyleDetails: {
    eatingHabit: oneOf(CLIENT_DIETS),
    aboutMe: text(1000),
  },
  familyDetails: {
    father: { occupation: text(100) },
    mother: { occupation: text(100) },
    familyType: oneOf(CLIENT_FAMILY_TYPES),
  },
  horoscopeDetails: {
    rashi: oneOf(CLIENT_RASHIS),
    star: oneOf(CLIENT_STARS),
  },
  partnerPreference: {
    preferredAgeRange: oneOf(CLIENT_PREF_AGE_RANGES),
    preferredHeightRange: oneOf(CLIENT_PREF_HEIGHT_RANGES),
    maritalStatusPref: oneOf(CLIENT_PREF_MARITAL_STATUSES),
    religionPref: oneOf(CLIENT_PREF_RELIGIONS),
    castePref: oneOf(CLIENT_PREF_CASTES),
    occupationPref: oneOf(CLIENT_PREF_OCCUPATIONS),
    incomePref: oneOf(CLIENT_PREF_INCOMES),
    locationPref: oneOf(CLIENT_PREF_LOCATIONS),
    extended: {
      minEducation: oneOf(CLIENT_PREF_MIN_EDUCATIONS),
      diet: oneOf(CLIENT_PREF_DIETS),
    },
  },
} as const satisfies Record<string, SectionRules>;

export type ClientProfileSection = keyof typeof CLIENT_PROFILE_FIELDS;

/**
 * The labels the server fills in from the master data. Accepted on input
 * only so a client can send back what it read (they are then ignored and
 * written again from the codes); never taken from the caller.
 */
export const CLIENT_PROFILE_LABELS: Partial<
  Record<ClientProfileSection, readonly string[]>
> = {
  religionDetails: ['religion', 'community'],
  locationDetails: ['country', 'state', 'city'],
};

export const MAX_CLIENT_SIBLINGS = 10;
const SIBLING_FIELDS: Record<string, Rule> = {
  relation: oneOf(CLIENT_SIBLING_RELATIONS),
  name: text(50),
  age: { kind: 'int', min: 0, max: 120 },
  occupation: text(100),
};

const CODE = /^[A-Z0-9][A-Z0-9_-]{0,39}$/;

/**
 * A client profile: wizard sections of plain values. Free-form on purpose
 * (`Record`), because its shape is the field table above, enforced by
 * `validateClientProfile`.
 */
export type ClientProfile = Partial<
  Record<ClientProfileSection, Record<string, unknown>>
>;

export type ClientProfileCheck =
  { ok: true; profile: ClientProfile } | { ok: false; fields: string[] };

const isObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

/** The value as the rule stores it, `undefined` for an empty answer, or `INVALID`. */
const INVALID = Symbol('invalid');
function checkValue(rule: Rule, value: unknown, now: Date): unknown {
  if (value === undefined || value === null) return undefined;
  if (rule.kind === 'int') {
    return Number.isSafeInteger(value) &&
      (value as number) >= rule.min &&
      (value as number) <= rule.max
      ? value
      : INVALID;
  }
  if (typeof value !== 'string') return INVALID;
  const trimmed = value.trim();
  if (trimmed === '') return undefined;
  switch (rule.kind) {
    case 'name':
      return [...trimmed].length <= 50 ? trimmed : INVALID;
    case 'text':
      return [...trimmed].length <= rule.max ? trimmed : INVALID;
    case 'oneOf':
      return rule.values.includes(trimmed) ? trimmed : INVALID;
    case 'dob':
      return /^\d{4}-\d{2}-\d{2}$/.test(trimmed) && isBirthDate(trimmed, now)
        ? trimmed
        : INVALID;
    case 'code': {
      const upper = trimmed.toUpperCase();
      return CODE.test(upper) ? upper : INVALID;
    }
  }
}

function checkFields(
  rules: Record<string, Rule | Record<string, Rule>>,
  input: Record<string, unknown>,
  path: string,
  now: Date,
  ignored: readonly string[],
  fields: string[],
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of Object.keys(input)) {
    if (!(key in rules) && !ignored.includes(key)) {
      fields.push(path);
      return out;
    }
  }
  for (const [key, rule] of Object.entries(rules)) {
    const value = input[key];
    if (!('kind' in rule)) {
      // A nested group (father, mother, extended).
      if (value === undefined || value === null) continue;
      if (!isObject(value)) {
        fields.push(`${path}.${key}`);
        continue;
      }
      const nested = checkFields(
        rule,
        value,
        `${path}.${key}`,
        now,
        [],
        fields,
      );
      if (Object.keys(nested).length > 0) out[key] = nested;
      continue;
    }
    const checked = checkValue(rule as Rule, value, now);
    if (checked === INVALID) fields.push(`${path}.${key}`);
    else if (checked !== undefined) out[key] = checked;
  }
  return out;
}

function checkSiblings(
  value: unknown,
  path: string,
  now: Date,
  fields: string[],
): Record<string, unknown>[] | undefined {
  if (value === undefined || value === null) return undefined;
  if (!Array.isArray(value) || value.length > MAX_CLIENT_SIBLINGS) {
    fields.push(path);
    return undefined;
  }
  const out: Record<string, unknown>[] = [];
  value.forEach((item, i) => {
    const at = `${path}[${i}]`;
    if (!isObject(item)) {
      fields.push(at);
      return;
    }
    const before = fields.length;
    const sibling = checkFields(SIBLING_FIELDS, item, at, now, [], fields);
    // A sibling is a brother or a sister: the wizard always records which.
    if (fields.length === before && sibling.relation === undefined) {
      fields.push(`${at}.relation`);
    }
    if (fields.length === before) out.push(sibling);
  });
  return out.length > 0 ? out : undefined;
}

/**
 * Checks and normalises (trims, upper-cases codes, drops empty answers) a
 * whole profile. Any field may be missing: completeness is judged at submit
 * (`missingRequiredClientFields`). `undefined` is an empty profile.
 */
export function validateClientProfile(
  input: unknown,
  now: Date,
): ClientProfileCheck {
  if (input === undefined || input === null) return { ok: true, profile: {} };
  if (!isObject(input)) return { ok: false, fields: ['details'] };
  const fields: string[] = [];
  const profile: ClientProfile = {};
  for (const key of Object.keys(input)) {
    if (!(key in CLIENT_PROFILE_FIELDS)) {
      return { ok: false, fields: ['details'] };
    }
  }
  for (const [section, rules] of Object.entries(CLIENT_PROFILE_FIELDS) as [
    ClientProfileSection,
    SectionRules,
  ][]) {
    const value = input[section];
    if (value === undefined || value === null) continue;
    const path = `details.${section}`;
    if (!isObject(value)) {
      fields.push(path);
      continue;
    }
    const isFamily = section === 'familyDetails';
    const ignored = [
      ...(CLIENT_PROFILE_LABELS[section] ?? []),
      ...(isFamily ? ['siblings'] : []),
    ];
    const checked = checkFields(rules, value, path, now, ignored, fields);
    if (isFamily) {
      const siblings = checkSiblings(
        value.siblings,
        `${path}.siblings`,
        now,
        fields,
      );
      if (siblings) checked.siblings = siblings;
    }
    if (Object.keys(checked).length > 0) profile[section] = checked;
  }
  return fields.length > 0 ? { ok: false, fields } : { ok: true, profile };
}

/** The required fields (`client-profile-required.ts`) this profile still lacks, in that list's order. */
export function missingRequiredClientFields(profile: ClientProfile): string[] {
  return CLIENT_PROFILE_REQUIRED_AT_SUBMIT.filter((path) => {
    const [section, field] = path.split('.') as [ClientProfileSection, string];
    const value = profile[section]?.[field];
    return typeof value !== 'string' || value.trim() === '';
  });
}

// --- Into the member's registration draft -------------------------------------

/**
 * The wizard's sections in step order (steps 1 to 10). Must equal
 * `DRAFT_SECTIONS` in profiles/services/profile-draft.service.ts (a spec
 * checks it).
 */
export const WIZARD_SECTIONS = [
  'basicDetails',
  'religionDetails',
  'languageDetails',
  'locationDetails',
  'educationDetails',
  'physicalDetails',
  'lifestyleDetails',
  'familyDetails',
  'horoscopeDetails',
  'partnerPreference',
] as const;

/** A Way 2 profile is always the client's own: the wizard's "Myself". */
export const CLIENT_PROFILE_CREATED_FOR = 'Myself';

export interface ClientWizardDraft {
  draftData: Record<string, Record<string, unknown>>;
  /** The wizard step of every section that holds an answer, ascending. */
  completedSteps: number[];
  /** The highest of them, as saving those sections in the app would leave it. */
  currentStep: number;
}

/**
 * The client's registration draft, exactly as the wizard would hold it had
 * she saved each filled section herself: every section the agent filled, in
 * the wizard's names and values (codes and their labels), with
 * `basicDetails.profileCreatedFor` set to "Myself".
 */
export function toClientWizardDraft(profile: ClientProfile): ClientWizardDraft {
  const draftData: Record<string, Record<string, unknown>> = {};
  const completedSteps: number[] = [];
  WIZARD_SECTIONS.forEach((section, index) => {
    const values = profile[section];
    const copy =
      section === 'basicDetails'
        ? {
            ...structuredClone(values ?? {}),
            profileCreatedFor: CLIENT_PROFILE_CREATED_FOR,
          }
        : values && Object.keys(values).length > 0
          ? structuredClone(values)
          : undefined;
    if (copy === undefined) return;
    draftData[section] = copy;
    completedSteps.push(index + 1);
  });
  return {
    draftData,
    completedSteps,
    currentStep: Math.max(...completedSteps),
  };
}

/**
 * Reads a profile back from its sealed JSON (already opened). A draft saved
 * before the full profile existed holds step 1 flat (with a
 * `profileCreatedFor`); it is read as its `basicDetails`, the old choice
 * dropped. Throws on anything else that is not an object: corrupt data.
 */
export function parseStoredClientProfile(json: string): ClientProfile {
  const parsed = JSON.parse(json) as unknown;
  if (!isObject(parsed)) {
    throw new TypeError('Stored client details are not an object.');
  }
  if (typeof parsed.firstName === 'string' && !('basicDetails' in parsed)) {
    const basic: Record<string, unknown> = {};
    for (const key of [
      'firstName',
      'lastName',
      'gender',
      'dob',
      'maritalStatus',
    ]) {
      if (typeof parsed[key] === 'string') basic[key] = parsed[key];
    }
    return { basicDetails: basic };
  }
  return parsed;
}
