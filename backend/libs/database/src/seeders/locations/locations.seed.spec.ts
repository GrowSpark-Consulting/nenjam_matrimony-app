import { resolve } from 'node:path';
import { loadDataset } from './index';

/**
 * Guards the committed dataset itself, not the code that reads it.
 *
 * `build_dataset.py` validates its own output, but the build script is not
 * what runs on deploy — the committed bytes are. A hand-edit, a bad merge or
 * a truncated file would otherwise surface as a failed production deploy or,
 * worse, a half-loaded location table.
 */
// locations -> seeders -> src -> database -> libs -> backend -> repo root
const SEED_DATA = resolve(__dirname, '../../../../../../seed-data');

describe('committed location dataset', () => {
  const dataset = loadDataset(SEED_DATA);

  it('parses and passes every structural check', () => {
    // loadDataset throws on the first problem, so reaching here is the
    // assertion. These make the expected scale explicit.
    expect(dataset.countries.length).toBe(8);
    expect(dataset.subdivisions.length).toBeGreaterThan(300);
    expect(dataset.cities.length).toBeGreaterThan(9000);
  });

  it('keys every city by its own subdivision code', () => {
    // The code is `{subdivision}-{normalized name}`, which is what makes it
    // deterministic and what the profile stores.
    for (const city of dataset.cities) {
      expect(city.code.startsWith(`${city.stateCode}-`)).toBe(true);
    }
  });

  it('holds the approved Singapore city-state exception', () => {
    const sgSg = dataset.subdivisions.find((s) => s.code === 'SG-SG');
    expect(sgSg).toMatchObject({ label: 'Singapore', type: 'City-state', isActive: true });

    const sgCities = dataset.cities.filter((c) => c.countryCode === 'SG');
    expect(sgCities.length).toBe(65);
    // Every one under SG-SG: ISO's SG-01..SG-05 cannot be matched to
    // GeoNames' data without guessing, so nothing was guessed.
    expect(sgCities.every((c) => c.stateCode === 'SG-SG')).toBe(true);
    for (const code of ['SG-01', 'SG-02', 'SG-03', 'SG-04', 'SG-05']) {
      expect(dataset.subdivisions.find((s) => s.code === code)?.isActive).toBe(false);
    }
  });

  it('holds the approved India current/retired handling', () => {
    const byCode = new Map(dataset.subdivisions.map((s) => [s.code, s]));
    // Added: the iso-3166-2 package predates both.
    expect(byCode.get('IN-LA')).toMatchObject({ label: 'Ladakh', isActive: true });
    expect(byCode.get('IN-DH')).toMatchObject({ isActive: true });
    // Retained but inactive: legacy values must stay resolvable while
    // staying out of registration dropdowns.
    expect(byCode.get('IN-DD')).toMatchObject({ isActive: false });
    expect(byCode.get('IN-DN')).toMatchObject({ isActive: false });
  });

  it('gives every active subdivision at least one city', () => {
    // The invariant the API relies on: a member can never pick a state and
    // then face an empty city list.
    const populated = new Set(dataset.cities.map((c) => c.stateCode));
    const empty = dataset.subdivisions
      .filter((s) => s.isActive && !populated.has(s.code))
      .map((s) => s.code);
    expect(empty).toEqual([]);
  });

  it('still contains the cities existing seed profiles live in', () => {
    // The Tamil Nadu seed profiles reference these. A dataset rebuild that
    // dropped them would break those profiles' location codes.
    const codes = new Set(dataset.cities.map((c) => c.code));
    expect(codes.has('IN-TN-CHENNAI')).toBe(true);
    expect(codes.has('IN-TN-COIMBATORE')).toBe(true);
    expect(codes.has('IN-TN-MADURAI')).toBe(true);
  });

  it('has no duplicate codes at any level', () => {
    const unique = (rows: { code: string }[]) => new Set(rows.map((r) => r.code)).size;
    expect(unique(dataset.countries)).toBe(dataset.countries.length);
    expect(unique(dataset.subdivisions)).toBe(dataset.subdivisions.length);
    expect(unique(dataset.cities)).toBe(dataset.cities.length);
  });
});
