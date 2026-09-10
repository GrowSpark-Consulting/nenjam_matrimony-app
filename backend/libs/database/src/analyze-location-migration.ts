/**
 * Entrypoint for `pnpm analyze:locations`.
 *
 * READ-ONLY. This script answers one question — "if we backfilled
 * country_code / state_code / city_code from the existing free text, what
 * would happen?" — and answers it without writing anything. There is no
 * update, no upsert and no delete anywhere in this file, deliberately: the
 * decision to backfill production is a human one, taken after reading this.
 *
 * The matching rule is intentionally strict. A profile is reported as
 * unambiguous only when its city text resolves to exactly ONE city, and that
 * city's state and country agree with the profile's own state and country
 * text. Everything else is reported as needing review, with the actual value
 * shown, so a person can decide. Nothing is guessed, and no fuzzy matching is
 * used — a near-miss is a miss.
 */
import { config } from 'dotenv';
import { PrismaPg } from '@prisma/adapter-pg';
import { resolve } from 'node:path';

config({ path: '.env' });
config({ path: '.env.local', override: true });

import { PrismaClient } from '../generated/client';
import { describeTarget } from './seeders/fake-profiles/seed-guard';

/** Same normalisation the dataset build uses: case, accents and punctuation
 *  are noise; anything else is a genuine difference. */
function norm(value: string | null | undefined): string {
  if (!value) return '';
  return value
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '');
}

interface Bucket {
  label: string;
  count: number;
  sample: string[];
}

function tally(map: Map<string, Bucket>, key: string, sample: string): void {
  const existing = map.get(key);
  if (existing) {
    existing.count++;
    if (existing.sample.length < 5 && !existing.sample.includes(sample)) {
      existing.sample.push(sample);
    }
  } else {
    map.set(key, { label: key, count: 1, sample: [sample] });
  }
}

async function main(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL?.trim();
  if (!databaseUrl) throw new Error('DATABASE_URL is not set.');
  const target = describeTarget(databaseUrl);

  const prisma = new PrismaClient({
    adapter: new PrismaPg({ connectionString: databaseUrl }),
  });

  try {
    const [countries, subdivisions, cities] = await Promise.all([
      prisma.country.findMany(),
      prisma.subdivision.findMany(),
      prisma.city.findMany(),
    ]);

    if (countries.length === 0) {
      throw new Error(
        'No location master data in this database. Run `pnpm seed:locations` first.',
      );
    }

    // Name -> codes. A name mapping to more than one code is ambiguous by
    // definition and is never auto-resolved.
    const countryByName = new Map<string, string[]>();
    for (const c of countries) {
      const key = norm(c.label);
      countryByName.set(key, [...(countryByName.get(key) ?? []), c.code]);
    }
    const stateByName = new Map<string, string[]>();
    for (const s of subdivisions) {
      const key = norm(s.label);
      stateByName.set(key, [...(stateByName.get(key) ?? []), s.code]);
    }
    const cityByName = new Map<string, string[]>();
    for (const c of cities) {
      const key = norm(c.label);
      cityByName.set(key, [...(cityByName.get(key) ?? []), c.code]);
    }
    const cityByCode = new Map(cities.map((c) => [c.code, c]));
    const stateByCode = new Map(subdivisions.map((s) => [s.code, s]));

    const profiles = await prisma.userProfile.findMany({
      select: {
        id: true,
        currentCity: true,
        currentState: true,
        country: true,
        countryCode: true,
        stateCode: true,
        cityCode: true,
      },
    });

    let alreadyCoded = 0;
    let fullyResolvable = 0;
    const reasons = new Map<string, Bucket>();
    const resolvableSamples: string[] = [];

    for (const p of profiles) {
      if (p.countryCode || p.stateCode || p.cityCode) {
        alreadyCoded++;
        continue;
      }

      const shown = `${p.currentCity} / ${p.currentState} / ${p.country ?? 'NULL'}`;

      const countryCodes = countryByName.get(norm(p.country)) ?? [];
      const stateCodes = stateByName.get(norm(p.currentState)) ?? [];
      const cityCodes = cityByName.get(norm(p.currentCity)) ?? [];

      if (!p.country) {
        tally(reasons, 'country is NULL — no country text to match on', shown);
        continue;
      }
      if (countryCodes.length === 0) {
        tally(reasons, `country text matches no country: "${p.country}"`, shown);
        continue;
      }
      if (stateCodes.length === 0) {
        tally(reasons, `state text matches no subdivision: "${p.currentState}"`, shown);
        continue;
      }
      if (stateCodes.length > 1) {
        tally(reasons, `state name is ambiguous across countries: "${p.currentState}"`, shown);
        continue;
      }
      if (cityCodes.length === 0) {
        tally(reasons, `city text matches no city: "${p.currentCity}"`, shown);
        continue;
      }
      if (cityCodes.length > 1) {
        // e.g. "Rajgarh" exists in both Rajasthan and Madhya Pradesh. The
        // state text usually disambiguates; only if it does not is this fatal.
        const inState = cityCodes.filter((c) => cityByCode.get(c)?.stateCode === stateCodes[0]);
        if (inState.length !== 1) {
          tally(
            reasons,
            `city name is ambiguous (${cityCodes.length} matches): "${p.currentCity}"`,
            shown,
          );
          continue;
        }
        cityCodes.splice(0, cityCodes.length, ...inState);
      }

      const city = cityByCode.get(cityCodes[0]);
      const state = stateByCode.get(stateCodes[0]);
      if (!city || !state) {
        tally(reasons, 'internal: resolved code not found in master data', shown);
        continue;
      }
      if (city.stateCode !== state.code) {
        tally(
          reasons,
          `city and state disagree: "${p.currentCity}" is in ${city.stateCode}, ` +
            `not "${p.currentState}" (${state.code})`,
          shown,
        );
        continue;
      }
      if (state.countryCode !== countryCodes[0]) {
        tally(
          reasons,
          `state and country disagree: "${p.currentState}" is in ${state.countryCode}, ` +
            `not "${p.country}" (${countryCodes[0]})`,
          shown,
        );
        continue;
      }

      fullyResolvable++;
      if (resolvableSamples.length < 8) {
        resolvableSamples.push(`${shown}  ->  ${city.code}`);
      }
    }

    const needsReview = profiles.length - alreadyCoded - fullyResolvable;

    console.log('');
    console.log('==================================================');
    console.log('LEGACY LOCATION MIGRATION ANALYSIS  (READ-ONLY)');
    console.log('==================================================');
    console.log(`Target : ${target.host} [${target.region}]`);
    console.log('');
    console.log(`Profiles examined            ${profiles.length}`);
    console.log(`  already have codes         ${alreadyCoded}`);
    console.log(`  unambiguously resolvable   ${fullyResolvable}`);
    console.log(`  need human review          ${needsReview}`);
    console.log('');

    if (resolvableSamples.length > 0) {
      console.log('Examples of what a backfill WOULD set:');
      for (const s of resolvableSamples) console.log(`  ${s}`);
      console.log('');
    }

    if (reasons.size > 0) {
      console.log('Why the rest are not resolvable:');
      console.log('--------------------------------------------------');
      for (const bucket of [...reasons.values()].sort((a, b) => b.count - a.count)) {
        console.log(`  ${String(bucket.count).padStart(5)}  ${bucket.label}`);
        for (const sample of bucket.sample) {
          console.log(`         e.g. ${sample}`);
        }
      }
      console.log('');
    }

    console.log('==================================================');
    console.log('Nothing was written. Every profile above still holds');
    console.log('exactly the location text its owner entered.');
    console.log('==================================================');
    console.log('');
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
