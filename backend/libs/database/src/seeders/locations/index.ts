/**
 * Loads the location master data in `seed-data/` into the database.
 *
 * Unlike the fake-profile seeder, this is real reference data, not test
 * fixtures — it is *meant* to run against production, and does so on every
 * deploy. Three properties make that safe:
 *
 *   Idempotent   Every write is an upsert keyed on the ISO code. Running it
 *                twice changes nothing the second time.
 *   Additive     It never deletes. A row that disappears from the dataset is
 *                deactivated, not removed, because a profile may reference it.
 *   Isolated     It touches only the three master tables. It never reads or
 *                writes user_profiles, so a member's location cannot change.
 */
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import type { PrismaClient } from '../../../generated/client';

/** Where the committed dataset lives, relative to `backend/`. */
export const SEED_DATA_DIR = join('..', 'seed-data');

/** Postgres caps a parameterized statement at 65,535 bindings; 500 rows of
 *  6 columns is 3,000, comfortably inside it while still cutting 9,308
 *  individual round trips to Singapore down to nineteen. */
const CHUNK = 500;

interface CountryRow {
  code: string;
  label: string;
  isActive: boolean;
}

interface SubdivisionRow {
  code: string;
  countryCode: string;
  label: string;
  type: string;
  isActive: boolean;
}

interface CityRow {
  code: string;
  stateCode: string;
  countryCode: string;
  label: string;
  population: number;
  isActive: boolean;
}

export interface LocationSeedReport {
  countries: number;
  subdivisions: number;
  cities: number;
  deactivated: number;
  checksum: string;
  unchanged: boolean;
}

/**
 * Minimal RFC 4180 field splitter — the dataset quotes every label, and a few
 * genuinely contain commas ("Washington, D.C."). Splitting on bare commas
 * would silently corrupt those, so quotes are honoured properly.
 */
function splitCsvLine(line: string): string[] {
  const fields: string[] = [];
  let field = '';
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQuotes) {
      if (ch === '"') {
        if (line[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === ',') {
      fields.push(field);
      field = '';
    } else {
      field += ch;
    }
  }
  fields.push(field);
  return fields;
}

function readDataset(dir: string): {
  countries: CountryRow[];
  subdivisions: SubdivisionRow[];
  cities: CityRow[];
  checksum: string;
} {
  const countriesRaw = readFileSync(join(dir, 'iso-3166-1-countries.json'), 'utf8');
  const subdivisionsRaw = readFileSync(join(dir, 'iso-3166-2-subdivisions.json'), 'utf8');
  const citiesRaw = readFileSync(join(dir, 'cities.csv'), 'utf8');

  const countries = JSON.parse(countriesRaw) as CountryRow[];
  const subdivisions = JSON.parse(subdivisionsRaw) as SubdivisionRow[];

  const lines = citiesRaw.split('\n').filter((l) => l.trim().length > 0);
  const header = lines.shift();
  const EXPECTED_HEADER = 'city_code,state_code,country_code,label,population';
  if (header?.trim() !== EXPECTED_HEADER) {
    throw new Error(
      `cities.csv header changed.\n  expected: ${EXPECTED_HEADER}\n  got:      ${header}`,
    );
  }

  const cities = lines.map((line, i) => {
    const [code, stateCode, countryCode, label, population] = splitCsvLine(line);
    const pop = Number(population);
    if (!code || !stateCode || !countryCode || !label || !Number.isInteger(pop)) {
      throw new Error(`cities.csv line ${i + 2} is malformed: ${line}`);
    }
    return { code, stateCode, countryCode, label, population: pop, isActive: true };
  });

  // The checksum covers the exact bytes of all three files, so the seeder can
  // tell "the dataset is unchanged" from "the dataset was rebuilt" without
  // comparing 9,308 rows.
  const checksum = createHash('sha256')
    .update(countriesRaw)
    .update(subdivisionsRaw)
    .update(citiesRaw)
    .digest('hex')
    .slice(0, 16);

  return { countries, subdivisions, cities, checksum };
}

/**
 * Validates the dataset against itself before a single row is written.
 *
 * The build script already checks all of this, but the build script is not
 * what runs on deploy — this file is, against whatever bytes are committed.
 * A bad dataset must fail here, before it can put the database in a state
 * where a member's registration references a subdivision that has no cities.
 */
function validate(
  countries: CountryRow[],
  subdivisions: SubdivisionRow[],
  cities: CityRow[],
): void {
  const errors: string[] = [];
  const countryCodes = new Set(countries.map((c) => c.code));
  const subByCode = new Map(subdivisions.map((s) => [s.code, s]));

  if (countryCodes.size !== countries.length) errors.push('duplicate country codes');
  if (subByCode.size !== subdivisions.length) errors.push('duplicate subdivision codes');
  if (new Set(cities.map((c) => c.code)).size !== cities.length) {
    errors.push('duplicate city codes');
  }

  for (const s of subdivisions) {
    if (!countryCodes.has(s.countryCode)) {
      errors.push(`subdivision ${s.code} references unknown country ${s.countryCode}`);
    }
  }

  const withCities = new Set<string>();
  for (const c of cities) {
    const parent = subByCode.get(c.stateCode);
    if (!parent) {
      errors.push(`city ${c.code} references unknown subdivision ${c.stateCode}`);
      continue;
    }
    if (!parent.isActive) {
      errors.push(`city ${c.code} sits under inactive subdivision ${c.stateCode}`);
    }
    // The denormalized country_code must agree with the parent's, or a
    // country-wide city query and a state-wide one would disagree.
    if (parent.countryCode !== c.countryCode) {
      errors.push(
        `city ${c.code} says country ${c.countryCode}, its subdivision says ${parent.countryCode}`,
      );
    }
    withCities.add(c.stateCode);
  }

  for (const s of subdivisions) {
    if (s.isActive && !withCities.has(s.code)) {
      errors.push(`active subdivision ${s.code} (${s.label}) has no cities`);
    }
  }

  if (errors.length > 0) {
    throw new Error(
      `Location dataset failed validation; nothing was written.\n` +
        errors.slice(0, 20).map((e) => `  - ${e}`).join('\n') +
        (errors.length > 20 ? `\n  ... and ${errors.length - 20} more` : ''),
    );
  }
}

async function chunked<T>(rows: T[], fn: (batch: T[]) => Promise<unknown>): Promise<void> {
  for (let i = 0; i < rows.length; i += CHUNK) {
    await fn(rows.slice(i, i + CHUNK));
  }
}

/**
 * Reads and validates the committed dataset without touching a database.
 *
 * Exported so a test can assert the files in `seed-data/` are sound, rather
 * than finding out during a deploy. Throws on the first problem.
 */
export function loadDataset(dir: string = SEED_DATA_DIR): {
  countries: CountryRow[];
  subdivisions: SubdivisionRow[];
  cities: CityRow[];
  checksum: string;
} {
  const dataset = readDataset(dir);
  validate(dataset.countries, dataset.subdivisions, dataset.cities);
  return dataset;
}

export async function seedLocations(
  prisma: PrismaClient,
  dir: string = SEED_DATA_DIR,
): Promise<LocationSeedReport> {
  const { countries, subdivisions, cities, checksum } = loadDataset(dir);

  // Parents before children, so a foreign key is never briefly unsatisfiable.
  // `createMany ... skipDuplicates` inserts what is new; the `updateMany`
  // that follows corrects labels and activity flags on what already existed.
  // Together they are an upsert that costs a handful of statements instead of
  // 9,308, and — crucially — never deletes.
  await chunked(countries, (batch) =>
    prisma.country.createMany({ data: batch, skipDuplicates: true }),
  );
  await chunked(subdivisions, (batch) =>
    prisma.subdivision.createMany({ data: batch, skipDuplicates: true }),
  );
  await chunked(cities, (batch) =>
    prisma.city.createMany({ data: batch, skipDuplicates: true }),
  );

  // Correct any row whose label, type, population or activity has changed
  // since it was first inserted. Only rows that actually differ are written.
  const existingCountries = await prisma.country.findMany();
  const existingSubs = await prisma.subdivision.findMany();
  const existingCities = await prisma.city.findMany();

  const byCode = <T extends { code: string }>(rows: T[]) =>
    new Map(rows.map((r) => [r.code, r]));
  const wantCountries = byCode(countries);
  const wantSubs = byCode(subdivisions);
  const wantCities = byCode(cities);

  let updates = 0;
  for (const row of existingCountries) {
    const want = wantCountries.get(row.code);
    if (want && (row.label !== want.label || row.isActive !== want.isActive)) {
      await prisma.country.update({
        where: { code: row.code },
        data: { label: want.label, isActive: want.isActive },
      });
      updates++;
    }
  }
  for (const row of existingSubs) {
    const want = wantSubs.get(row.code);
    if (
      want &&
      (row.label !== want.label || row.type !== want.type || row.isActive !== want.isActive)
    ) {
      await prisma.subdivision.update({
        where: { code: row.code },
        data: { label: want.label, type: want.type, isActive: want.isActive },
      });
      updates++;
    }
  }
  for (const row of existingCities) {
    const want = wantCities.get(row.code);
    if (
      want &&
      (row.label !== want.label ||
        row.population !== want.population ||
        row.isActive !== want.isActive)
    ) {
      await prisma.city.update({
        where: { code: row.code },
        data: { label: want.label, population: want.population, isActive: want.isActive },
      });
      updates++;
    }
  }

  // A row in the database but no longer in the dataset is DEACTIVATED, never
  // deleted: a member may already have it stored on their profile, and the
  // foreign key is ON DELETE RESTRICT precisely so that a delete here would
  // fail loudly rather than blank someone's location.
  let deactivated = 0;
  const stale = <T extends { code: string; isActive: boolean }>(
    existing: T[],
    want: Map<string, unknown>,
  ) => existing.filter((r) => r.isActive && !want.has(r.code)).map((r) => r.code);

  const staleCities = stale(existingCities, wantCities);
  const staleSubs = stale(existingSubs, wantSubs);
  const staleCountries = stale(existingCountries, wantCountries);
  if (staleCities.length > 0) {
    await prisma.city.updateMany({
      where: { code: { in: staleCities } },
      data: { isActive: false },
    });
    deactivated += staleCities.length;
  }
  if (staleSubs.length > 0) {
    await prisma.subdivision.updateMany({
      where: { code: { in: staleSubs } },
      data: { isActive: false },
    });
    deactivated += staleSubs.length;
  }
  if (staleCountries.length > 0) {
    await prisma.country.updateMany({
      where: { code: { in: staleCountries } },
      data: { isActive: false },
    });
    deactivated += staleCountries.length;
  }

  return {
    countries: countries.length,
    subdivisions: subdivisions.length,
    cities: cities.length,
    deactivated,
    checksum,
    unchanged:
      updates === 0 &&
      deactivated === 0 &&
      existingCountries.length === countries.length &&
      existingSubs.length === subdivisions.length &&
      existingCities.length === cities.length,
  };
}
