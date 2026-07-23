// Single source of truth for "is this wizard step complete" across the
// registration flow. Mirrored (by hand — see each Dart class's
// `isComplete`/`isTouched` getters in
// Frontend/lib/features/registration/domain/models/profile_draft.dart) so the
// Continue-button gating on the client and the finalize()-time enforcement on
// the server never diverge. Keep both sides in sync when these rules change.
//
// Steps 1-4 are hard-required (no Skip button) — every listed field must be
// present. Steps 5, 6, 7 and 9 are skippable, but if the user engages with
// them at all the section must be fully completed: a section is valid if
// it's entirely untouched OR fully filled — only a partial fill is invalid.
// This needs no persisted "skipped" flag; it's purely a function of the
// draft data itself.

type Section = Record<string, unknown>;

// The literal string "Other" is never a valid, complete answer — it's the
// chip-selection placeholder for fields with a custom "Other" option
// (religion, country, state, qualification, occupation, disability, annual
// income). The Flutter widget backing those fields (OtherOptionField) never
// emits this literal value once wired correctly, but this is the
// authoritative server-side check: if it ever arrives literally (a stale
// client, a raw API call), treat it exactly like an empty field rather than
// accepting it as completed data.
const has = (value: unknown): boolean =>
  typeof value === 'string'
    ? value.trim().length > 0 && value.trim() !== 'Other'
    : value != null;

const hasNonEmptyArray = (value: unknown): boolean =>
  Array.isArray(value) && value.length > 0;

const allPresent = (section: Section, fields: string[]): boolean =>
  fields.every((field) => has(section[field]));

const anyPresent = (section: Section, fields: string[]): boolean =>
  fields.some((field) => has(section[field]));

// ---- Steps 1-4: always required ----

export function isBasicDetailsComplete(basic: Section): boolean {
  return allPresent(basic, [
    'firstName',
    'lastName',
    'gender',
    'maritalStatus',
    'profileCreatedFor',
    'dob',
  ]);
}

export function isReligionDetailsComplete(religion: Section): boolean {
  return allPresent(religion, ['religion', 'caste', 'subCaste', 'community']);
}

export function isLanguageDetailsComplete(language: Section): boolean {
  return (
    has(language.motherTongue) && hasNonEmptyArray(language.languagesKnown)
  );
}

export function isLocationDetailsComplete(location: Section): boolean {
  return allPresent(location, [
    'country',
    'state',
    'city',
    'area',
    'pinCode',
    'nativePlace',
  ]);
}

// ---- Steps 5, 6, 7: skippable, all-required-if-touched ----

const EDUCATION_FIELDS = [
  'qualification',
  'college',
  'occupation',
  'company',
  'employmentType',
  'annualIncome',
  'workLocation',
];

export function isEducationSectionTouched(education: Section): boolean {
  return anyPresent(education, EDUCATION_FIELDS);
}

export function isEducationDetailsValid(education: Section): boolean {
  return (
    !isEducationSectionTouched(education) ||
    allPresent(education, EDUCATION_FIELDS)
  );
}

// Physical "touched" only looks at height/weight — `disability` defaults to
// `'None'` on the client, which is always non-empty, so including it here
// would make the section read as "touched" even when the user never
// interacted with the page at all.
const PHYSICAL_TOUCH_FIELDS = ['height', 'weight'];
const PHYSICAL_REQUIRED_FIELDS = ['height', 'weight', 'disability'];

export function isPhysicalSectionTouched(physical: Section): boolean {
  return anyPresent(physical, PHYSICAL_TOUCH_FIELDS);
}

export function isPhysicalDetailsValid(physical: Section): boolean {
  return (
    !isPhysicalSectionTouched(physical) ||
    allPresent(physical, PHYSICAL_REQUIRED_FIELDS)
  );
}

const LIFESTYLE_SCALAR_FIELDS = [
  'eatingHabit',
  'smoking',
  'drinking',
  'fitness',
  'aboutMe',
];

export function isLifestyleSectionTouched(lifestyle: Section): boolean {
  return (
    anyPresent(lifestyle, LIFESTYLE_SCALAR_FIELDS) ||
    hasNonEmptyArray(lifestyle.hobbies)
  );
}

export function isLifestyleDetailsValid(lifestyle: Section): boolean {
  if (!isLifestyleSectionTouched(lifestyle)) return true;
  return (
    allPresent(lifestyle, LIFESTYLE_SCALAR_FIELDS) &&
    hasNonEmptyArray(lifestyle.hobbies)
  );
}

// ---- Step 9: skippable, Rashi required-if-touched ----

const HOROSCOPE_TOUCH_FIELDS = [
  'birthTime',
  'birthPlace',
  'rashi',
  'nakshatra',
  'star',
  'manglik',
  'dosham',
];

export function isHoroscopeSectionTouched(horoscope: Section): boolean {
  return (
    anyPresent(horoscope, HOROSCOPE_TOUCH_FIELDS) ||
    Boolean(horoscope.horoscopeAvailable)
  );
}

export function isHoroscopeDetailsValid(horoscope: Section): boolean {
  return !isHoroscopeSectionTouched(horoscope) || has(horoscope.rashi);
}
