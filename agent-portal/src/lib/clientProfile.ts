import type { ClientDetails } from '../api/types';

/**
 * The Way 2 client profile: field schema, height labels, and the pure helpers
 * that keep a PATCH safe. Source of truth: docs/agent-program/
 * HANDOFF_WAY2_FRONTEND.md section 5a and agent-api.openapi.yaml.
 *
 * PATCH replaces the WHOLE `details`, so every save sends the complete merged
 * profile built here, never one section.
 */

export type Option = { value: string; label: string };
export type RefKind = 'religion' | 'community' | 'country' | 'state' | 'city';

export type FieldDef = {
  /** Dotted path inside `details`, e.g. `basicDetails.firstName`. */
  path: string;
  label: string;
  kind: 'text' | 'longtext' | 'date' | 'choice' | 'ref';
  options?: Option[];
  ref?: RefKind;
  maxLength?: number;
};

export type SectionDef =
  | { key: string; title: string; fields: FieldDef[]; siblings?: false }
  | { key: string; title: string; fields: FieldDef[]; siblings: true };

const same = (...v: string[]): Option[] => v.map((x) => ({ value: x, label: x }));

/** `5'9" (175 cm)` for every whole cm in 122..213: the member app's own formula. */
export function heightLabel(cm: number): string {
  const totalInches = Math.round(cm / 2.54);
  return `${Math.floor(totalInches / 12)}'${totalInches % 12}" (${cm} cm)`;
}
export const MIN_HEIGHT_CM = 122;
export const MAX_HEIGHT_CM = 213;
export const HEIGHT_OPTIONS: Option[] = Array.from(
  { length: MAX_HEIGHT_CM - MIN_HEIGHT_CM + 1 },
  (_, i) => {
    const label = heightLabel(MIN_HEIGHT_CM + i);
    return { value: label, label };
  },
);

/** The nine paths the server needs to submit (`x-required-at-submit`). */
export const REQUIRED_PATHS = [
  'basicDetails.firstName',
  'basicDetails.lastName',
  'basicDetails.gender',
  'basicDetails.dob',
  'basicDetails.maritalStatus',
  'religionDetails.religionCode',
  'locationDetails.stateCode',
  'locationDetails.cityCode',
  'educationDetails.qualification',
] as const;

export const SECTIONS: SectionDef[] = [
  {
    key: 'basicDetails',
    title: 'Basic details',
    fields: [
      { path: 'basicDetails.firstName', label: 'First name', kind: 'text', maxLength: 50 },
      { path: 'basicDetails.lastName', label: 'Last name', kind: 'text', maxLength: 50 },
      {
        path: 'basicDetails.gender',
        label: 'Gender',
        kind: 'choice',
        options: [
          { value: 'MALE', label: 'Male' },
          { value: 'FEMALE', label: 'Female' },
        ],
      },
      { path: 'basicDetails.dob', label: 'Date of birth', kind: 'date' },
      {
        path: 'basicDetails.maritalStatus',
        label: 'Marital status',
        kind: 'choice',
        options: [
          { value: 'NEVER_MARRIED', label: 'Never married' },
          { value: 'DIVORCED', label: 'Divorced' },
          { value: 'WIDOWED', label: 'Widowed' },
          { value: 'AWAITING_DIVORCE', label: 'Awaiting divorce' },
        ],
      },
    ],
  },
  {
    key: 'religionDetails',
    title: 'Religion',
    fields: [
      { path: 'religionDetails.religionCode', label: 'Religion', kind: 'ref', ref: 'religion' },
      { path: 'religionDetails.communityCode', label: 'Community', kind: 'ref', ref: 'community' },
      { path: 'religionDetails.subCaste', label: 'Sub-community', kind: 'text', maxLength: 50 },
    ],
  },
  {
    key: 'languageDetails',
    title: 'Language',
    fields: [{ path: 'languageDetails.motherTongue', label: 'Mother tongue', kind: 'text', maxLength: 50 }],
  },
  {
    key: 'locationDetails',
    title: 'Location',
    fields: [
      { path: 'locationDetails.countryCode', label: 'Country', kind: 'ref', ref: 'country' },
      { path: 'locationDetails.stateCode', label: 'State', kind: 'ref', ref: 'state' },
      { path: 'locationDetails.cityCode', label: 'City', kind: 'ref', ref: 'city' },
      { path: 'locationDetails.nativePlace', label: 'Native place', kind: 'text', maxLength: 100 },
    ],
  },
  {
    key: 'educationDetails',
    title: 'Education and work',
    fields: [
      { path: 'educationDetails.qualification', label: 'Highest education', kind: 'text', maxLength: 100 },
      { path: 'educationDetails.occupation', label: 'Occupation', kind: 'text', maxLength: 100 },
      {
        path: 'educationDetails.employmentType',
        label: 'Employer type',
        kind: 'choice',
        options: same('Private', 'Government', 'Business', 'Self-Employed', 'Not Working', 'Student', 'Retired'),
      },
      {
        path: 'educationDetails.annualIncome',
        label: 'Yearly income',
        kind: 'choice',
        options: same('Below 5 Lakhs', '5 - 10 Lakhs', '10 - 20 Lakhs', '20 - 50 Lakhs', '50 Lakhs - 1 Crore', '1 Crore+'),
      },
    ],
  },
  {
    key: 'physicalDetails',
    title: 'Physical',
    fields: [{ path: 'physicalDetails.height', label: 'Height', kind: 'choice', options: HEIGHT_OPTIONS }],
  },
  {
    key: 'lifestyleDetails',
    title: 'Lifestyle',
    fields: [
      {
        path: 'lifestyleDetails.eatingHabit',
        label: 'Diet',
        kind: 'choice',
        options: same('Vegetarian', 'Non-Vegetarian', 'Eggetarian', 'Vegan', 'Jain'),
      },
      { path: 'lifestyleDetails.aboutMe', label: 'About the client', kind: 'longtext', maxLength: 1000 },
    ],
  },
  {
    key: 'familyDetails',
    title: 'Family',
    siblings: true,
    fields: [
      { path: 'familyDetails.father.occupation', label: "Father's occupation", kind: 'text', maxLength: 100 },
      { path: 'familyDetails.mother.occupation', label: "Mother's occupation", kind: 'text', maxLength: 100 },
      {
        path: 'familyDetails.familyType',
        label: 'Family type',
        kind: 'choice',
        options: same('Joint Family', 'Nuclear Family'),
      },
    ],
  },
  {
    key: 'horoscopeDetails',
    title: 'Horoscope',
    fields: [
      {
        path: 'horoscopeDetails.rashi',
        label: 'Zodiac (rashi)',
        kind: 'choice',
        options: same('Mesha', 'Vrishabha', 'Mithuna', 'Kataka', 'Simha', 'Kanya', 'Tula', 'Vrischika', 'Dhanu', 'Makara', 'Kumbha', 'Meena', "Don't Know"),
      },
      {
        path: 'horoscopeDetails.star',
        label: 'Star',
        kind: 'choice',
        options: same(
          'Aswini', 'Bharani', 'Karthigai', 'Rohini', 'Mrigasheersham', 'Thiruvaathirai', 'Punarpoosam', 'Poosam', 'Aayilyam',
          'Magam', 'Pooram', 'Uthiram', 'Hastham', 'Chithirai', 'Swaathi', 'Visaagam', 'Anusham', 'Kettai', 'Moolam',
          'Pooraadam', 'Uthiraadam', 'Thiruvonam', 'Avittam', 'Sadhayam', 'Poorattathi', 'Uthirattathi', 'Revathi', "Don't Know",
        ),
      },
    ],
  },
  {
    key: 'partnerPreference',
    title: 'Partner preferences',
    fields: [
      { path: 'partnerPreference.preferredAgeRange', label: 'Age range', kind: 'choice', options: same('18-22', '22-26', '26-30', '30-35', '35-40', '40-50', 'Any') },
      { path: 'partnerPreference.preferredHeightRange', label: 'Height range', kind: 'choice', options: same('4\'6"-5\'0"', '5\'0"-5\'4"', '5\'4"-5\'8"', '5\'8"-6\'0"', '6\'0"+', 'Any') },
      { path: 'partnerPreference.maritalStatusPref', label: 'Marital status', kind: 'choice', options: same('Never Married', "Doesn't Matter", 'Any') },
      { path: 'partnerPreference.religionPref', label: 'Religion', kind: 'choice', options: same('Hindu', 'Christian', 'Muslim', 'Jain', 'Sikh', 'Any') },
      { path: 'partnerPreference.castePref', label: 'Communities', kind: 'choice', options: same('Same Caste', 'Any Caste', 'Inter-Caste OK') },
      { path: 'partnerPreference.extended.minEducation', label: 'Minimum education', kind: 'choice', options: same('High School', 'Bachelors', 'Masters', 'Doctorate', 'Any') },
      { path: 'partnerPreference.occupationPref', label: 'Occupation type', kind: 'choice', options: same('Software / IT', 'Doctor', 'Government', 'Business', 'Any') },
      { path: 'partnerPreference.incomePref', label: 'Income range', kind: 'choice', options: same('5-10 Lakhs', '10-20 Lakhs', '20-50 Lakhs', '50 Lakhs+', 'Any') },
      { path: 'partnerPreference.locationPref', label: 'Locations', kind: 'choice', options: same('Same City', 'Same State', 'Anywhere in India', 'NRI OK', 'Any') },
      { path: 'partnerPreference.extended.diet', label: 'Diet', kind: 'choice', options: same('Vegetarian', 'Eggetarian', 'Vegan', 'Non-Vegetarian', "Doesn't Matter") },
    ],
  },
];

/** Master-data label fields the server fills in; never sent as answers. */
const LABEL_KEYS: Record<string, string[]> = {
  religionDetails: ['religion', 'community'],
  locationDetails: ['country', 'state', 'city'],
};

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => typeof v === 'object' && v !== null && !Array.isArray(v);

export function getPath(details: ClientDetails | null | undefined, path: string): unknown {
  let cur: unknown = details;
  for (const part of path.split('.')) {
    if (!isObj(cur)) return undefined;
    cur = cur[part];
  }
  return cur;
}

/** Immutable set. Returns a new tree; the input is never touched. */
export function setPath(details: ClientDetails, path: string, value: unknown): ClientDetails {
  const [head, ...rest] = path.split('.');
  const next: Obj = { ...details };
  if (rest.length === 0) {
    next[head] = value;
  } else {
    next[head] = setPath(isObj(next[head]) ? (next[head] as Obj) : {}, rest.join('.'), value);
  }
  return next;
}

/** Fields that depend on a parent and must be cleared when it changes. */
const CHILDREN: Record<string, string[]> = {
  'religionDetails.religionCode': ['religionDetails.communityCode'],
  'locationDetails.countryCode': ['locationDetails.stateCode', 'locationDetails.cityCode'],
  'locationDetails.stateCode': ['locationDetails.cityCode'],
};

/** Sets one answer in the complete draft, clearing dependants when a parent changes. */
export function setAnswer(details: ClientDetails, path: string, value: string): ClientDetails {
  if (getPath(details, path) === value) return details;
  let next = setPath(details, path, value);
  for (const child of CHILDREN[path] ?? []) next = setPath(next, child, undefined);
  return next;
}

/** True for the "not answered" values the backend drops. */
function unanswered(v: unknown): boolean {
  return v === undefined || v === null || (typeof v === 'string' && v.trim() === '');
}

export type SiblingRow = { relation?: string; name?: string; age?: string | number; occupation?: string };

export interface Normalized {
  details: ClientDetails;
  /** Paths the agent must fix before this can be sent (sibling rules). */
  errors: { path: string; message: string }[];
}

function pruneObject(value: Obj): Obj | undefined {
  const out: Obj = {};
  for (const [k, v] of Object.entries(value)) {
    if (isObj(v)) {
      const inner = pruneObject(v);
      if (inner) out[k] = inner;
    } else if (typeof v === 'string') {
      if (v.trim() !== '') out[k] = v.trim();
    } else if (!unanswered(v) && !Array.isArray(v)) {
      out[k] = v;
    }
  }
  return Object.keys(out).length > 0 ? out : undefined;
}

/**
 * Turns the working draft into the body for the server: only what the agent
 * answered. Unanswered fields (missing / null / "" / spaces) are omitted,
 * sections left empty are omitted (so is `partnerPreference`), label fields
 * are dropped, sibling rows are checked. Pure: never mutates [details].
 */
export function normalizeDetails(details: ClientDetails): Normalized {
  const errors: Normalized['errors'] = [];
  const out: Obj = {};
  for (const [section, raw] of Object.entries(details)) {
    if (!isObj(raw)) continue;
    const body: Obj = { ...raw };
    for (const k of LABEL_KEYS[section] ?? []) delete body[k];
    const siblingsRaw = body.siblings;
    delete body.siblings;
    const pruned = pruneObject(body) ?? {};

    if (section === 'familyDetails' && Array.isArray(siblingsRaw)) {
      const rows: Obj[] = [];
      siblingsRaw.forEach((row, i) => {
        if (!isObj(row)) return;
        const r = row as SiblingRow;
        const cells: Obj = {};
        for (const k of ['relation', 'name', 'occupation'] as const) {
          const v = r[k];
          if (typeof v === 'string' && v.trim() !== '') cells[k] = v.trim();
        }
        const age = r.age;
        if (typeof age === 'number') {
          cells.age = age;
        } else if (typeof age === 'string' && age.trim() !== '') {
          const n = Number(age.trim());
          if (Number.isInteger(n) && n >= 0 && n <= 120) cells.age = n;
          else errors.push({ path: `familyDetails.siblings[${i}].age`, message: 'Age must be a whole number from 0 to 120.' });
        }
        if (Object.keys(cells).length === 0) return; // an empty row is just left out
        if (!cells.relation) {
          errors.push({ path: `familyDetails.siblings[${i}].relation`, message: 'Choose brother or sister for each sibling.' });
          return;
        }
        rows.push(cells);
      });
      if (rows.length > 0) (pruned as Obj).siblings = rows;
    }
    if (Object.keys(pruned).length > 0) out[section] = pruned;
  }
  return { details: out, errors };
}

/** The section that owns a path like `educationDetails.qualification` or `familyDetails.siblings[0].relation`. */
export function sectionOf(path: string): string {
  return path.split(/[.[]/)[0];
}

/** Whether [path] is a master-data code answered with an unanswered value. */
export function isAnswered(details: ClientDetails | null | undefined, path: string): boolean {
  return !unanswered(getPath(details, path));
}
