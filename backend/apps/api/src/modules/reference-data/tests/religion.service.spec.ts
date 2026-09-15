import { NotFoundException } from '@nestjs/common';
import { ReligionService } from '../services/religion.service';
import type { PrismaService } from '@app/database';

const RELIGIONS = [
  { code: 'HINDU', label: 'Hindu', isActive: true },
  { code: 'JAIN', label: 'Jain', isActive: true },
  // A religion that exists but is no longer offered. Kept resolvable so an
  // existing member holding it can still save unrelated edits.
  { code: 'RETIRED', label: 'Retired Faith', isActive: false },
  // A religion with no communities at all — a real, empty answer.
  { code: 'INTER-RELIGION', label: 'Inter-Religion', isActive: true },
];

const COMMUNITIES = [
  { code: 'HINDU-VELLALAR', religionCode: 'HINDU', label: 'Vellalar', isActive: true },
  { code: 'HINDU-IYER', religionCode: 'HINDU', label: 'Iyer', isActive: true },
  { code: 'HINDU-NADAR', religionCode: 'HINDU', label: 'Nadar', isActive: true },
  { code: 'JAIN-DIGAMBAR', religionCode: 'JAIN', label: 'Digambar', isActive: true },
  { code: 'JAIN-RETIRED', religionCode: 'JAIN', label: 'Retired Community', isActive: false },
];

/**
 * A `findMany` that actually applies `where` / `orderBy` / `select`, so a
 * service that stopped filtering would produce wrong rows rather than quietly
 * passing. Same approach as the location service's fake.
 */
function fakeFindMany<T extends Record<string, unknown>>(rows: T[]) {
  return jest.fn(async (args: any = {}) => {
    let out = rows.filter((row) =>
      Object.entries(args.where ?? {}).every(([field, value]) => row[field] === value),
    );
    const orderBy = Array.isArray(args.orderBy) ? args.orderBy : args.orderBy ? [args.orderBy] : [];
    out = [...out].sort((a, b) => {
      for (const clause of orderBy) {
        const [field, dir] = Object.entries(clause)[0] as [string, 'asc' | 'desc'];
        const cmp = String(a[field]).localeCompare(String(b[field]));
        if (cmp !== 0) return dir === 'desc' ? -cmp : cmp;
      }
      return 0;
    });
    const select = args.select as Record<string, boolean> | undefined;
    if (!select) return out;
    return out.map((row) =>
      Object.fromEntries(Object.keys(select).map((k) => [k, row[k]])),
    );
  });
}

function fakeFindUnique<T extends Record<string, unknown>>(rows: T[]) {
  return jest.fn(async (args: any) => {
    const row = rows.find((r) => r.code === args.where.code);
    if (!row) return null;
    const select = args.select as Record<string, boolean> | undefined;
    if (!select) return row;
    return Object.fromEntries(Object.keys(select).map((k) => [k, row[k]]));
  });
}

function queryOf(service: ReligionService, model: 'religion' | 'community'): jest.Mock {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (service as any).prisma[model].findMany as jest.Mock;
}

function buildService(): ReligionService {
  const prisma = {
    religion: { findMany: fakeFindMany(RELIGIONS), findUnique: fakeFindUnique(RELIGIONS) },
    community: { findMany: fakeFindMany(COMMUNITIES), findUnique: fakeFindUnique(COMMUNITIES) },
  } as unknown as PrismaService;
  return new ReligionService(prisma);
}

describe('ReligionService — religions', () => {
  it('lists only active religions by default, and all of them on request', async () => {
    const service = buildService();
    expect((await service.listReligions()).map((r) => r.code)).toEqual([
      'HINDU',
      'INTER-RELIGION',
      'JAIN',
    ]);
    expect((await service.listReligions(true)).map((r) => r.code)).toContain('RETIRED');
  });

  it('selects only the columns the UI renders', async () => {
    const service = buildService();
    await service.listReligions();
    const [args] = queryOf(service, 'religion').mock.calls[0];
    expect(Object.keys(args.select).sort()).toEqual(['code', 'label']);
  });
});

describe('ReligionService — communities', () => {
  it('returns only the chosen religion\'s communities, alphabetically', async () => {
    const service = buildService();
    const communities = await service.listCommunities('HINDU');
    expect(communities.map((c) => c.label)).toEqual(['Iyer', 'Nadar', 'Vellalar']);
    // Never a community from another religion.
    expect(communities.every((c) => c.religionCode === 'HINDU')).toBe(true);
  });

  it('omits an inactive community but still lists it on request', async () => {
    const service = buildService();
    expect((await service.listCommunities('JAIN')).map((c) => c.code)).toEqual([
      'JAIN-DIGAMBAR',
    ]);
    expect((await service.listCommunities('JAIN', true)).map((c) => c.code)).toContain(
      'JAIN-RETIRED',
    );
  });

  it('returns an empty list for a religion that genuinely has none', async () => {
    const service = buildService();
    await expect(service.listCommunities('INTER-RELIGION')).resolves.toEqual([]);
  });

  it('404s an unknown religion rather than returning an empty list', async () => {
    // An empty array would read as "this religion has no communities", which
    // is a very different thing from "no such religion".
    const service = buildService();
    await expect(service.listCommunities('NOPE')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('never queries more than one religion of communities', async () => {
    const service = buildService();
    await service.listCommunities('HINDU');
    await service.listCommunities('JAIN');
    for (const [args] of queryOf(service, 'community').mock.calls) {
      expect(args.where.religionCode).toBeDefined();
    }
  });

  it('serves a repeated read from memory without re-querying', async () => {
    const service = buildService();
    const community = queryOf(service, 'community');
    await service.listCommunities('HINDU');
    expect(community).toHaveBeenCalledTimes(1);
    await service.listCommunities('HINDU');
    await service.listCommunities('HINDU');
    expect(community).toHaveBeenCalledTimes(1);
  });

  it('collapses concurrent first-time reads into a single query', async () => {
    const service = buildService();
    const community = queryOf(service, 'community');
    const results = await Promise.all([
      service.listCommunities('HINDU'),
      service.listCommunities('HINDU'),
      service.listCommunities('HINDU'),
    ]);
    expect(community).toHaveBeenCalledTimes(1);
    expect(results[0]).toEqual(results[2]);
  });

  it('does not memoise an empty result', async () => {
    // Far more likely an unseeded database than a real answer; caching it
    // would leave the dropdown empty until the next deploy.
    const service = buildService();
    const community = queryOf(service, 'community');
    await service.listCommunities('INTER-RELIGION');
    await service.listCommunities('INTER-RELIGION');
    expect(community).toHaveBeenCalledTimes(2);
  });
});

describe('ReligionService.resolve', () => {
  it('returns null when no codes are supplied, so older clients still save', async () => {
    const service = buildService();
    await expect(service.resolve({})).resolves.toBeNull();
    await expect(
      service.resolve({ religionCode: null, communityCode: null }),
    ).resolves.toBeNull();
  });

  it('resolves a valid pair to its canonical codes and labels', async () => {
    const service = buildService();
    await expect(
      service.resolve({ religionCode: 'HINDU', communityCode: 'HINDU-IYER' }),
    ).resolves.toEqual({
      religionCode: 'HINDU',
      communityCode: 'HINDU-IYER',
      religionLabel: 'Hindu',
      communityLabel: 'Iyer',
    });
  });

  it('accepts lowercase codes', async () => {
    const service = buildService();
    const resolved = await service.resolve({
      religionCode: 'hindu',
      communityCode: 'hindu-iyer',
    });
    expect(resolved?.communityCode).toBe('HINDU-IYER');
  });

  it('refuses a community that belongs to a different religion', async () => {
    // The whole point of server-side validation: a hand-crafted request
    // cannot file a Jain community under Hinduism.
    const service = buildService();
    await expect(
      service.resolve({ religionCode: 'HINDU', communityCode: 'JAIN-DIGAMBAR' }),
    ).rejects.toThrow(/not a Hindu community/);
  });

  it('refuses a community without its religion', async () => {
    const service = buildService();
    await expect(service.resolve({ communityCode: 'HINDU-IYER' })).rejects.toThrow(
      /must be accompanied by its religion code/,
    );
  });

  it('refuses codes that name nothing', async () => {
    const service = buildService();
    await expect(service.resolve({ religionCode: 'NOPE' })).rejects.toThrow(
      /Unknown religion/,
    );
    await expect(
      service.resolve({ religionCode: 'HINDU', communityCode: 'HINDU-NOPE' }),
    ).rejects.toThrow(/Unknown community/);
  });

  it('still resolves a retired religion, so an existing member can save other edits', async () => {
    const service = buildService();
    await expect(service.resolve({ religionCode: 'RETIRED' })).resolves.toMatchObject({
      religionCode: 'RETIRED',
      religionLabel: 'Retired Faith',
    });
  });
});
