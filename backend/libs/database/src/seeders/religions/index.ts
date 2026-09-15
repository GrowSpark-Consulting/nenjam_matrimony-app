/**
 * Loads the religion/community master data in `seed-data/religions.json`.
 *
 * Same three properties as the location seeder, for the same reasons: it is
 * meant to run on deploy, including against production.
 *
 *   Idempotent   Every write is an upsert keyed on the code.
 *   Additive     It never deletes. A row that disappears from the dataset is
 *                deactivated, because a profile may already name it.
 *   Isolated     It touches only the two master tables. It never reads or
 *                writes user_profiles, so no member's religion or community
 *                can change.
 */
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import type { PrismaClient } from '../../../generated/client';

/** Where the committed dataset lives, relative to `backend/`. */
export const RELIGION_SEED_FILE = join('..', 'seed-data', 'religions.json');

interface ReligionSource {
  code: string;
  label: string;
  communities: string[];
}

export interface ReligionSeedReport {
  religions: number;
  communities: number;
  deactivated: number;
  unchanged: boolean;
}

/**
 * `{religion code}-{normalized label}` — the same derivation city codes use,
 * so HINDU-VELLALAR is reproducible from its parts and a reseed never
 * produces a different code for the same community.
 */
export function communityCode(religionCode: string, label: string): string {
  const slug = label
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return `${religionCode}-${slug}`;
}

export function loadReligionDataset(file: string = RELIGION_SEED_FILE): {
  religions: ReligionSource[];
  communities: { code: string; religionCode: string; label: string }[];
} {
  const parsed = JSON.parse(readFileSync(file, 'utf8')) as {
    religions?: ReligionSource[];
  };
  const religions = parsed.religions;
  if (!Array.isArray(religions) || religions.length === 0) {
    throw new Error(`${file} contains no religions.`);
  }

  const errors: string[] = [];
  const seenReligion = new Set<string>();
  const communities: { code: string; religionCode: string; label: string }[] = [];
  const seenCommunity = new Set<string>();

  for (const religion of religions) {
    if (!religion.code || !religion.label) {
      errors.push(`a religion is missing code or label`);
      continue;
    }
    if (seenReligion.has(religion.code)) {
      errors.push(`duplicate religion code ${religion.code}`);
    }
    seenReligion.add(religion.code);

    for (const label of religion.communities ?? []) {
      const code = communityCode(religion.code, label);
      // A religion listing the same community twice would collide on code.
      if (seenCommunity.has(code)) {
        errors.push(`duplicate community ${code}`);
        continue;
      }
      seenCommunity.add(code);
      communities.push({ code, religionCode: religion.code, label });
    }
  }

  if (errors.length > 0) {
    throw new Error(
      `Religion dataset failed validation; nothing was written.\n` +
        errors.map((e) => `  - ${e}`).join('\n'),
    );
  }

  return { religions, communities };
}

export async function seedReligions(
  prisma: PrismaClient,
  file: string = RELIGION_SEED_FILE,
): Promise<ReligionSeedReport> {
  const { religions, communities } = loadReligionDataset(file);

  // Parents before children, so the foreign key is never briefly unsatisfiable.
  await prisma.religion.createMany({
    data: religions.map((r) => ({ code: r.code, label: r.label, isActive: true })),
    skipDuplicates: true,
  });
  await prisma.community.createMany({
    data: communities.map((c) => ({ ...c, isActive: true })),
    skipDuplicates: true,
  });

  // Correct labels / activity on rows that already existed.
  let updates = 0;
  const existingReligions = await prisma.religion.findMany();
  const existingCommunities = await prisma.community.findMany();
  const wantReligion = new Map(religions.map((r) => [r.code, r]));
  const wantCommunity = new Map(communities.map((c) => [c.code, c]));

  for (const row of existingReligions) {
    const want = wantReligion.get(row.code);
    if (want && (row.label !== want.label || !row.isActive)) {
      await prisma.religion.update({
        where: { code: row.code },
        data: { label: want.label, isActive: true },
      });
      updates++;
    }
  }
  for (const row of existingCommunities) {
    const want = wantCommunity.get(row.code);
    if (want && (row.label !== want.label || !row.isActive)) {
      await prisma.community.update({
        where: { code: row.code },
        data: { label: want.label, isActive: true },
      });
      updates++;
    }
  }

  // Gone from the dataset means DEACTIVATED, never deleted: a member may
  // already hold the value, and the foreign key is ON DELETE RESTRICT
  // precisely so a delete here would fail loudly rather than orphan a row.
  let deactivated = 0;
  const staleCommunities = existingCommunities
    .filter((c) => c.isActive && !wantCommunity.has(c.code))
    .map((c) => c.code);
  const staleReligions = existingReligions
    .filter((r) => r.isActive && !wantReligion.has(r.code))
    .map((r) => r.code);

  if (staleCommunities.length > 0) {
    await prisma.community.updateMany({
      where: { code: { in: staleCommunities } },
      data: { isActive: false },
    });
    deactivated += staleCommunities.length;
  }
  if (staleReligions.length > 0) {
    await prisma.religion.updateMany({
      where: { code: { in: staleReligions } },
      data: { isActive: false },
    });
    deactivated += staleReligions.length;
  }

  return {
    religions: religions.length,
    communities: communities.length,
    deactivated,
    unchanged:
      updates === 0 &&
      deactivated === 0 &&
      existingReligions.length === religions.length &&
      existingCommunities.length === communities.length,
  };
}
