import { parseBirthDate } from './birth-date';

/**
 * The registration answers a profile is expected to carry, field by field.
 *
 * `registration-rules.ts` answers section-shaped questions — "may this draft
 * be finalized", "can this row be written". This answers a narrower and more
 * useful one for the member: **which specific answers are still missing**. The
 * completion percentage used to be able to say only "the registration module
 * is incomplete", which told someone with nineteen of twenty answers exactly
 * as much as it told someone with none.
 *
 * The list and its order are the Edit Profile section's, so "field 7 is
 * missing" and "the seventh control on the screen is empty" are the same
 * statement. `wizardStep` is the step page to open to fix it.
 *
 * Nothing here is a second copy of the option lists. Whether a value is
 * *offered* is the client's question (ProfileOptions) and the DTOs'; this only
 * asks whether an answer is present and meaningful.
 */

/** Draft section a field lives on — the key inside `draft_data`. */
export type DraftSectionName =
  | 'basicDetails'
  | 'religionDetails'
  | 'locationDetails'
  | 'educationDetails'
  | 'physicalDetails'
  | 'lifestyleDetails';

export interface RequiredProfileField {
  /** Stable id the client uses to label and deep-link the field. */
  id: string;
  /** Section in `draft_data`. */
  section: DraftSectionName;
  /** Key within that section. */
  key: string;
  /** Wizard step page that edits it, matching the Flutter step indices. */
  wizardStep: number;
  /** Optional fields are listed but never counted — see `subCommunity`. */
  optional?: boolean;
}

/**
 * The twenty-one fields, in the order Edit Profile presents them.
 *
 * Twenty are required. `subCommunity` is listed so the client can render it
 * in place and show it as answered when it is, but it never counts toward the
 * score in either direction — leaving it blank must not cost a member
 * anything.
 */
export const REQUIRED_PROFILE_FIELDS: readonly RequiredProfileField[] = [
  {
    id: 'profileCreatedFor',
    section: 'basicDetails',
    key: 'profileCreatedFor',
    wizardStep: 0,
  },
  { id: 'gender', section: 'basicDetails', key: 'gender', wizardStep: 0 },
  { id: 'firstName', section: 'basicDetails', key: 'firstName', wizardStep: 0 },
  { id: 'lastName', section: 'basicDetails', key: 'lastName', wizardStep: 0 },
  { id: 'dob', section: 'basicDetails', key: 'dob', wizardStep: 0 },
  {
    id: 'religion',
    section: 'religionDetails',
    key: 'religion',
    wizardStep: 1,
  },
  {
    id: 'community',
    section: 'religionDetails',
    key: 'community',
    wizardStep: 1,
  },
  { id: 'country', section: 'locationDetails', key: 'country', wizardStep: 3 },
  { id: 'state', section: 'locationDetails', key: 'state', wizardStep: 3 },
  { id: 'city', section: 'locationDetails', key: 'city', wizardStep: 3 },
  {
    id: 'subCommunity',
    section: 'religionDetails',
    key: 'subCaste',
    wizardStep: 1,
    optional: true,
  },
  {
    id: 'maritalStatus',
    section: 'basicDetails',
    key: 'maritalStatus',
    wizardStep: 0,
  },
  { id: 'height', section: 'physicalDetails', key: 'height', wizardStep: 5 },
  {
    id: 'diet',
    section: 'lifestyleDetails',
    key: 'eatingHabit',
    wizardStep: 6,
  },
  {
    id: 'qualification',
    section: 'educationDetails',
    key: 'qualification',
    wizardStep: 4,
  },
  { id: 'college', section: 'educationDetails', key: 'college', wizardStep: 4 },
  {
    id: 'annualIncome',
    section: 'educationDetails',
    key: 'annualIncome',
    wizardStep: 4,
  },
  {
    id: 'employmentType',
    section: 'educationDetails',
    key: 'employmentType',
    wizardStep: 4,
  },
  {
    id: 'workIndustry',
    section: 'educationDetails',
    key: 'workIndustry',
    wizardStep: 4,
  },
  {
    id: 'occupation',
    section: 'educationDetails',
    key: 'occupation',
    wizardStep: 4,
  },
  { id: 'company', section: 'educationDetails', key: 'company', wizardStep: 4 },
];

/**
 * The profile photo, as a registration item.
 *
 * Not a `draft_data` field — photo count comes from the photo table — but it
 * IS part of what registration asks for, so it belongs in the same group and
 * the same 60%. Its wizard step is the photos step.
 */
export const PROFILE_PHOTO_ITEM = {
  id: 'photo',
  section: 'photos' as const,
  wizardStep: 11,
};

/** The twenty draft fields that count. */
export const COUNTED_PROFILE_FIELDS = REQUIRED_PROFILE_FIELDS.filter(
  (field) => !field.optional,
);

/**
 * Placeholder strings that are never an answer, whatever a client sends.
 *
 * `Other` is the important one. It is the selection placeholder on every
 * dropdown that pairs with a free-text box (`OtherOptionField`): choosing it
 * reveals the box, and the widget persists what the member *types* — never
 * the literal word. So a stored `"Other"` means the member picked "Other" and
 * gave nothing, which is an unanswered field, not a completed one. This is the
 * same rule `registration-rules.ts` applies with its own `has()`; both exist
 * because they are consulted at different moments, and both must agree.
 */
const PLACEHOLDER_VALUES = new Set(['other', 'select', 'none', 'n/a', '-']);

/**
 * Whether [value] is a real answer.
 *
 * Empty, whitespace, a placeholder, or an empty collection are all "not
 * answered". A number or boolean is taken at face value — those come from
 * controls that cannot produce a placeholder.
 */
export function isMeaningfulValue(value: unknown): boolean {
  if (value == null) return false;
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed.length === 0) return false;
    return !PLACEHOLDER_VALUES.has(trimmed.toLowerCase());
  }
  if (Array.isArray(value)) return value.length > 0;
  if (typeof value === 'object') return Object.keys(value).length > 0;
  return true;
}

/**
 * Whether one field is answered.
 *
 * `dob` is the exception: presence is not enough, because a stored date that
 * names no real day cannot be written to the column and would show the member
 * a completed field they cannot save. It is parsed with exactly the parser the
 * write path uses. The age floor is deliberately NOT applied — a member who
 * registered under the previous floor of 18 has a real date of birth and must
 * not be told their profile is incomplete over it.
 */
export function isFieldAnswered(
  field: RequiredProfileField,
  data: Record<string, Record<string, unknown> | undefined>,
): boolean {
  const value = (data[field.section] ?? {})[field.key];
  if (field.id === 'dob') return parseBirthDate(value) !== null;
  return isMeaningfulValue(value);
}

export interface RequiredFieldStatus {
  id: string;
  /** Draft section, or 'photos' for the profile-photo item. */
  section: DraftSectionName | 'photos';
  wizardStep: number;
  isComplete: boolean;
  optional: boolean;
}

/** Every field with its answered/unanswered state, in screen order. */
export function requiredFieldStatuses(
  data: Record<string, Record<string, unknown> | undefined>,
): RequiredFieldStatus[] {
  return REQUIRED_PROFILE_FIELDS.map((field) => ({
    id: field.id,
    section: field.section,
    wizardStep: field.wizardStep,
    isComplete: isFieldAnswered(field, data),
    optional: field.optional === true,
  }));
}

/**
 * How many of the counted fields are answered.
 *
 * Optional fields are excluded from both numerator and denominator, so
 * answering or skipping sub-community moves nothing.
 */
export function requiredFieldScore(
  data: Record<string, Record<string, unknown> | undefined>,
): { completed: number; total: number } {
  const completed = COUNTED_PROFILE_FIELDS.filter((field) =>
    isFieldAnswered(field, data),
  ).length;
  return { completed, total: COUNTED_PROFILE_FIELDS.length };
}

// ─── The registration group: the 20 counted fields plus the photo ─────

/**
 * Total registration items that count toward the 60%: the twenty counted
 * draft fields, plus at least one profile photo.
 */
export const REGISTRATION_ITEM_COUNT = COUNTED_PROFILE_FIELDS.length + 1;

/**
 * Every registration item with its answered state — the 21 draft fields in
 * screen order, then the photo.
 *
 * This is what the client renders as "Registration information". It stays
 * populated even when everything is answered, so the UI can show it as done;
 * `registrationComplete` is the flag that decides whether to hide the group.
 */
export function registrationItemStatuses(
  data: Record<string, Record<string, unknown> | undefined>,
  hasPhoto: boolean,
): RequiredFieldStatus[] {
  return [
    ...requiredFieldStatuses(data),
    {
      id: PROFILE_PHOTO_ITEM.id,
      section: PROFILE_PHOTO_ITEM.section,
      wizardStep: PROFILE_PHOTO_ITEM.wizardStep,
      isComplete: hasPhoto,
      optional: false,
    },
  ];
}

/**
 * How many registration items are answered, out of
 * {@link REGISTRATION_ITEM_COUNT}.
 *
 * Sub-community is excluded from both numerator and denominator, so answering
 * or skipping it moves nothing.
 */
export function registrationScore(
  data: Record<string, Record<string, unknown> | undefined>,
  hasPhoto: boolean,
): { completed: number; total: number } {
  const { completed } = requiredFieldScore(data);
  return {
    completed: completed + (hasPhoto ? 1 : 0),
    total: REGISTRATION_ITEM_COUNT,
  };
}
