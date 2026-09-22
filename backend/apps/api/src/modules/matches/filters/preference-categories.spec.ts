import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
import {
  EDUCATION_CATEGORIES,
  OCCUPATION_CATEGORIES,
  PROFILE_OCCUPATIONS,
  PROFILE_QUALIFICATIONS,
} from './preference-categories';
import {
  buildFeedWhere,
  resolveEducation,
  resolveOccupations,
} from './partner-preference-where.builder';

/**
 * Education and occupation preferences were never applied: the picker offers
 * categories ("B.E / B.Tech+") that no profile stores, and every value on both
 * sides contains "/", which the generic resolver drops as a UI label. These pin
 * the mapping, the behaviour, and — by reading the Flutter source — that the
 * mapping still describes options a member can actually pick.
 */

// backend/apps/api/src/modules/matches/filters → repo root
const REPO_ROOT = join(__dirname, '..', '..', '..', '..', '..', '..', '..');
const PROFILE_OPTIONS = join(
  REPO_ROOT,
  'Frontend/lib/core/constants/profile_options.dart',
);
const PREF_LABELS = join(
  REPO_ROOT,
  'Frontend/lib/features/registration/presentation/utils/partner_preference_labels.dart',
);

/** The string literals of `name = [ ... ];` in a Dart source file. */
function dartList(file: string, name: string): string[] {
  const src = readFileSync(file, 'utf8');
  const match = new RegExp(
    `${name}\\s*=\\s*(?:<String>)?\\[(.*?)\\];`,
    's',
  ).exec(src);
  if (!match) throw new Error(`${name} not found in ${file}`);
  return [...match[1].matchAll(/'((?:\\'|[^'])*)'/g)].map((m) =>
    m[1].replace(/\\'/g, "'"),
  );
}

describe('preference categories match what the app offers', () => {
  const haveFlutter = existsSync(PROFILE_OPTIONS) && existsSync(PREF_LABELS);
  const itWithFlutter = haveFlutter ? it : it.skip;

  itWithFlutter('profile qualifications are exactly the app’s list', () => {
    expect([...PROFILE_QUALIFICATIONS]).toEqual(
      dartList(PROFILE_OPTIONS, 'qualifications'),
    );
  });

  itWithFlutter('profile occupations are exactly the app’s list', () => {
    expect([...PROFILE_OCCUPATIONS]).toEqual(
      dartList(PROFILE_OPTIONS, 'occupations'),
    );
  });

  itWithFlutter('every preference category is an option in the picker', () => {
    const education = dartList(PREF_LABELS, 'partnerPrefEducations');
    const occupations = dartList(PREF_LABELS, 'partnerPrefOccupations');
    for (const label of Object.keys(EDUCATION_CATEGORIES)) {
      expect(education).toContain(label);
    }
    for (const label of Object.keys(OCCUPATION_CATEGORIES)) {
      expect(occupations).toContain(label);
    }
  });

  itWithFlutter(
    'every picker option is either mapped or means "no preference"',
    () => {
      // A new option added to the app without a mapping here would silently
      // filter on a label no profile stores — this catches it.
      for (const label of dartList(PREF_LABELS, 'partnerPrefEducations')) {
        expect({
          label,
          resolved: resolveEducation([label]).length > 0 || /any/i.test(label),
        }).toEqual({ label, resolved: true });
      }
      for (const label of dartList(PREF_LABELS, 'partnerPrefOccupations')) {
        expect({
          label,
          resolved:
            resolveOccupations([label]).length > 0 || /any/i.test(label),
        }).toEqual({ label, resolved: true });
      }
    },
  );

  it('every mapped value is a real profile value', () => {
    for (const values of Object.values(EDUCATION_CATEGORIES)) {
      for (const v of values) expect(PROFILE_QUALIFICATIONS).toContain(v);
    }
    for (const values of Object.values(OCCUPATION_CATEGORIES)) {
      for (const v of values) expect(PROFILE_OCCUPATIONS).toContain(v);
    }
  });
});

describe('resolveEducation / resolveOccupations', () => {
  it('"+" means this level or higher', () => {
    expect(resolveEducation(['B.E / B.Tech+'])).toEqual([
      'B.E / B.Tech',
      'M.Tech / M.E',
      'Ph.D',
    ]);
    expect(resolveEducation(['MBA+'])).toEqual(['MBA / PGDM', 'Ph.D']);
    expect(resolveEducation(['MBBS / MD+'])).toEqual(['MBBS / MD']);
  });

  it('maps occupation categories to profile values', () => {
    expect(resolveOccupations(['Software / IT'])).toEqual([
      'Software Engineer',
    ]);
    expect(resolveOccupations(['Government'])).toEqual(['IAS / IPS / Govt']);
    expect(resolveOccupations(['Business'])).toEqual(['Business Owner']);
    expect(resolveOccupations(['Doctor'])).toEqual(['Doctor']);
  });

  it('keeps an exact profile value even though it contains "/"', () => {
    expect(resolveEducation(['B.Sc / M.Sc'])).toEqual(['B.Sc / M.Sc']);
    expect(resolveOccupations(['Teacher / Professor'])).toEqual([
      'Teacher / Professor',
    ]);
  });

  it('treats "Any" as no preference', () => {
    expect(resolveEducation(['Any Degree'])).toEqual([]);
    expect(resolveEducation(['Any'])).toEqual([]);
    expect(resolveOccupations(['Any'])).toEqual([]);
  });

  it('merges several choices without duplicates', () => {
    // Ph.D is covered by both categories — listed once.
    expect(resolveEducation(['B.E / B.Tech+', 'MBA+'])).toEqual([
      'B.E / B.Tech',
      'M.Tech / M.E',
      'Ph.D',
      'MBA / PGDM',
    ]);
  });

  it('is case-insensitive on the way in and canonical on the way out', () => {
    expect(resolveEducation(['b.e / b.tech+'])).toEqual([
      'B.E / B.Tech',
      'M.Tech / M.E',
      'Ph.D',
    ]);
  });

  it('keeps free-text legacy values working as before', () => {
    expect(resolveOccupations(['Pilot'])).toEqual(['Pilot']);
  });
});

describe('the feed filter now applies them', () => {
  const where = (pref: object) =>
    JSON.stringify(
      buildFeedWhere({
        currentUserId: 'me',
        myGender: 'MALE',
        self: null,
        pref,
      }),
    );

  it('filters education by the mapped profile values', () => {
    const json = where({ preferredEducation: ['B.E / B.Tech+'] });
    expect(json).toContain('"highestEducation":{"equals":"B.E / B.Tech"');
    expect(json).toContain('"highestEducation":{"equals":"M.Tech / M.E"');
    expect(json).toContain('"highestEducation":{"equals":"Ph.D"');
  });

  it('filters occupation by the mapped profile values', () => {
    expect(where({ preferredOccupations: ['Software / IT'] })).toContain(
      '"profession":{"equals":"Software Engineer"',
    );
  });

  it('adds no education filter for "Any Degree"', () => {
    expect(where({ preferredEducation: ['Any Degree'] })).not.toContain(
      'highestEducation',
    );
  });
});
