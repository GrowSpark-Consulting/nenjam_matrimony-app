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

// ---- Matchable: the narrower "can this draft become a UserProfile row?" ----

/**
 * Whether a draft carries enough to WRITE a `user_profiles` row.
 *
 * Deliberately weaker than the four rules above, and for a different
 * question. Those answer "may this profile be finalized?" — a product
 * contract, enforced by `finalize()`, which is unchanged. This one answers
 * "can the row physically be written?", and the honest answer is: every
 * NOT NULL column the write fills, and nothing more.
 *
 * The distinction had teeth. `syncMatchableFromDraft` reused the finalize
 * rules, so it silently returned for any draft missing `subCaste`, `area`,
 * `pinCode` or `nativePlace` — all four of which are NULLABLE columns the
 * write already coerces with `|| null`. The onboarding flow collects none of
 * them, so a member who changed their city there had it saved to
 * `draft_data` and never propagated to `user_profiles`; Discover, matching
 * and Near Me all read the stale row. Confirmed against live data: a draft
 * reading `Karnataka/Mysore` against a profile still reading
 * `Karnataka/hcufi`, plus 3 more blocked drafts.
 *
 * Fields listed here are exactly those the profile write passes without a
 * null fallback — see `ProfileService.writeProfileFromDraft`. `languagesKnown`
 * is absent on purpose (the column has a `[]` default), as are `community`,
 * `subCaste`, `country`, `area`, `pinCode` and `nativeCity`, which are all
 * nullable. `profileCreatedFor` is absent because it is not a profile column
 * at all.
 *
 * Nothing here is invented to make a draft pass: a draft still missing a
 * genuinely NOT NULL value (`caste`, say) stays blocked, which is correct —
 * the alternative is writing a fabricated value into someone's profile.
 */
export function isMatchableFromDraft(
  data: Record<string, Section | undefined>,
): boolean {
  const basic = data.basicDetails ?? {};
  const religion = data.religionDetails ?? {};
  const language = data.languageDetails ?? {};
  const location = data.locationDetails ?? {};

  return (
    allPresent(basic, ['firstName', 'lastName', 'gender', 'maritalStatus', 'dob']) &&
    allPresent(religion, ['religion', 'caste']) &&
    has(language.motherTongue) &&
    allPresent(location, ['state', 'city'])
  );
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

// ---- Step 8: skippable, no required-if-touched rule ----
//
// Family Details has no all-or-nothing rule in the wizard itself (partially
// filled father/mother/sibling rows are fine) — but ProfileCompletionService
// still needs a single yes/no gate for its 10% slice. familyType and
// familyValues are the two fields ProfileDraftService's legacy field-count
// formula already treated as "the" required pair for this section; reused
// here so the completion gate matches what the wizard UI has always implied
// is the section's core.
const FAMILY_TOUCH_FIELDS = ['familyType', 'familyValues', 'familyStatus'];

export function isFamilySectionTouched(family: Section): boolean {
  const father = (family.father ?? {}) as Section;
  const mother = (family.mother ?? {}) as Section;
  return (
    anyPresent(family, FAMILY_TOUCH_FIELDS) ||
    has(father.name) ||
    has(mother.name) ||
    hasNonEmptyArray(family.siblings)
  );
}

export function isFamilyDetailsComplete(family: Section): boolean {
  return has(family.familyType) && has(family.familyValues);
}

// ---- Step 11: skippable, genuinely no required-if-touched rule ----
//
// Unlike Education/Physical/Lifestyle/Horoscope, Partner Preference has no
// "all fields required once you touch any" rule anywhere in the system:
// every field on PartnerPreferenceDto (backend) is @IsOptional(), and the
// standalone Partner Preferences page's Save button
// (features/partner_preferences/presentation/pages/partner_preferences_page.dart)
// has no validation gate — any subset of filters, including a single one,
// is a complete, save-able preference set by product design (it's a filter
// list, not a form describing one fact about the user). So there is no
// distinct "touched but invalid" state to guard against here — touched and
// complete are the same thing. isPartnerPreferenceComplete is this
// function's real name for that reason; it is not a stricter check layered
// on top of "touched", it is a confirmed alias of it.
const PARTNER_PREFERENCE_FIELDS = [
  'preferredAgeRange',
  'preferredHeightRange',
  'religionPref',
  'castePref',
  'educationPref',
  'occupationPref',
  'incomePref',
  'locationPref',
  'motherTonguePref',
  'maritalStatusPref',
];

export function isPartnerPreferenceTouched(partnerPref: Section): boolean {
  if (anyPresent(partnerPref, PARTNER_PREFERENCE_FIELDS)) return true;
  const extended = partnerPref.extended;
  return (
    extended != null &&
    typeof extended === 'object' &&
    Object.keys(extended).length > 0
  );
}

export function isPartnerPreferenceComplete(partnerPref: Section): boolean {
  return isPartnerPreferenceTouched(partnerPref);
}
