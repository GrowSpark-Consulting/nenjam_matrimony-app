import { NotFoundException } from '@nestjs/common';
import { LocationService } from '../services/location.service';
import type { PrismaService } from '@app/database';

/**
 * A deliberately small dataset that still contains every shape the real one
 * does: an active country, an inactive subdivision retained for legacy
 * lookups, the Singapore city-state exception, and two same-named cities in
 * different countries.
 */
const COUNTRIES = [
  { code: 'IN', label: 'India', isActive: true },
  { code: 'SG', label: 'Singapore', isActive: true },
  { code: 'AU', label: 'Australia', isActive: true },
  { code: 'XX', label: 'Retired Country', isActive: false },
];

const SUBDIVISIONS = [
  { code: 'IN-TN', countryCode: 'IN', label: 'Tamil Nadu', type: 'State', isActive: true },
  { code: 'IN-KL', countryCode: 'IN', label: 'Kerala', type: 'State', isActive: true },
  {
    code: 'IN-DD',
    countryCode: 'IN',
    label: 'Daman and Diu',
    type: 'Union territory',
    isActive: false,
  },
  { code: 'SG-SG', countryCode: 'SG', label: 'Singapore', type: 'City-state', isActive: true },
  { code: 'AU-NSW', countryCode: 'AU', label: 'New South Wales', type: 'State', isActive: true },
];

const CITIES = [
  { code: 'IN-TN-CHENNAI', stateCode: 'IN-TN', countryCode: 'IN', label: 'Chennai', population: 4646732, isActive: true },
  { code: 'IN-TN-COIMBATORE', stateCode: 'IN-TN', countryCode: 'IN', label: 'Coimbatore', population: 959823, isActive: true },
  { code: 'IN-TN-CHENGALPATTU', stateCode: 'IN-TN', countryCode: 'IN', label: 'Chengalpattu', population: 62579, isActive: true },
  { code: 'IN-TN-KANCHIPURAM', stateCode: 'IN-TN', countryCode: 'IN', label: 'Kanchipuram', population: 164384, isActive: true },
  { code: 'IN-KL-KOCHI', stateCode: 'IN-KL', countryCode: 'IN', label: 'Kochi', population: 601574, isActive: true },
  { code: 'IN-DD-DAMAN', stateCode: 'IN-DD', countryCode: 'IN', label: 'Daman', population: 39737, isActive: false },
  { code: 'SG-SG-SINGAPORE', stateCode: 'SG-SG', countryCode: 'SG', label: 'Singapore', population: 3547809, isActive: true },
  // Real populations from the committed dataset. Newcastle is 13x the size of
  // Castle Hill, which is what makes the prefix-ranking test below meaningful.
  { code: 'AU-NSW-NEWCASTLE', stateCode: 'AU-NSW', countryCode: 'AU', label: 'Newcastle', population: 508437, isActive: true },
  { code: 'AU-NSW-CASTLEHILL', stateCode: 'AU-NSW', countryCode: 'AU', label: 'Castle Hill', population: 39284, isActive: true },
];

/**
 * A fake `findMany` that actually applies `where` / `orderBy` / `take` /
 * `skip`, rather than returning the fixtures whatever it is asked.
 *
 * This matters now that filtering, ordering and paging happen in Postgres
 * instead of in Node: a mock that ignored the query would let the service
 * stop passing `where: { isActive: true }` and every test would still pass.
 * Here, a wrong query produces wrong rows.
 */
function fakeFindMany<T extends Record<string, unknown>>(rows: T[]) {
  return jest.fn(async (args: any = {}) => {
    let out = [...rows];

    for (const [field, condition] of Object.entries(args.where ?? {})) {
      out = out.filter((row) => {
        const value = row[field];
        // `{ contains, mode: 'insensitive' }` — the only operator used here.
        if (condition && typeof condition === 'object' && 'contains' in condition) {
          const { contains, mode } = condition as { contains: string; mode?: string };
          return mode === 'insensitive'
            ? String(value).toLowerCase().includes(contains.toLowerCase())
            : String(value).includes(contains);
        }
        return value === condition;
      });
    }

    const orderBy = Array.isArray(args.orderBy)
      ? args.orderBy
      : args.orderBy
        ? [args.orderBy]
        : [];
    out.sort((a, b) => {
      for (const clause of orderBy) {
        const [field, direction] = Object.entries(clause)[0] as [string, 'asc' | 'desc'];
        const x = a[field];
        const y = b[field];
        if (x === y) continue;
        const cmp =
          typeof x === 'number' && typeof y === 'number'
            ? x - y
            : String(x).localeCompare(String(y));
        return direction === 'desc' ? -cmp : cmp;
      }
      return 0;
    });

    if (args.skip) out = out.slice(args.skip);
    if (args.take) out = out.slice(0, args.take);

    // Honour `select`, so a test can catch the service over-fetching columns.
    const select = args.select as Record<string, boolean> | undefined;
    if (!select) return out;
    return out.map((row) =>
      Object.fromEntries(Object.keys(select).map((key) => [key, row[key]])),
    );
  });
}

/** The `findMany` mock behind one model, for asserting what was queried. */
function queryOf(service: LocationService, model: 'country' | 'subdivision' | 'city'): jest.Mock {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return (service as any).prisma[model].findMany as jest.Mock;
}

/** Primary-key lookup that honours `select`, like the real client. */
function fakeFindUnique<T extends Record<string, unknown>>(rows: T[]) {
  return jest.fn(async (args: any) => {
    const row = rows.find((r) => r.code === args.where.code);
    if (!row) return null;
    const select = args.select as Record<string, boolean> | undefined;
    if (!select) return row;
    return Object.fromEntries(Object.keys(select).map((k) => [k, row[k]]));
  });
}

function buildService(): LocationService {
  const prisma = {
    country: { findMany: fakeFindMany(COUNTRIES), findUnique: fakeFindUnique(COUNTRIES) },
    subdivision: {
      findMany: fakeFindMany(SUBDIVISIONS),
      findUnique: fakeFindUnique(SUBDIVISIONS),
    },
    city: { findMany: fakeFindMany(CITIES), findUnique: fakeFindUnique(CITIES) },
  } as unknown as PrismaService;
  return new LocationService(prisma);
}

describe('LocationService reads', () => {
  it('lists only active countries by default, and all of them on request', async () => {
    const service = buildService();
    expect((await service.listCountries()).map((c) => c.code)).toEqual(['AU', 'IN', 'SG']);
    expect((await service.listCountries(true)).map((c) => c.code)).toContain('XX');
  });

  it('omits a retired subdivision from the dropdown but still lists it on request', async () => {
    const service = buildService();
    const active = await service.listSubdivisions('IN');
    expect(active.map((s) => s.code)).toEqual(['IN-KL', 'IN-TN']);
    expect(active.map((s) => s.code)).not.toContain('IN-DD');

    const all = await service.listSubdivisions('IN', true);
    expect(all.map((s) => s.code)).toContain('IN-DD');
  });

  it('rejects an unknown country rather than returning an empty list', async () => {
    const service = buildService();
    // An empty array would look to the client like "this country has no
    // states", which is a very different thing from "no such country".
    await expect(service.listSubdivisions('ZZ')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('returns cities largest first, so the big ones are visible before typing', async () => {
    const service = buildService();
    const cities = await service.listCities('IN-TN');
    expect(cities.map((c) => c.label)).toEqual([
      'Chennai',
      'Coimbatore',
      'Kanchipuram',
      'Chengalpattu',
    ]);
  });

  it('ranks prefix matches above substring matches, even much larger ones', async () => {
    const service = buildService();
    // Newcastle is 13x the size of Castle Hill and would win on population
    // alone, but someone typing "cast" means Castle Hill.
    const cities = await service.listCities('AU-NSW', { search: 'cast' });
    expect(cities.map((c) => c.label)).toEqual(['Castle Hill', 'Newcastle']);
  });

  it('honours the limit against the largest-first ordering', async () => {
    const service = buildService();
    const cities = await service.listCities('IN-TN', { limit: 2 });
    expect(cities.map((c) => c.label)).toEqual(['Chennai', 'Coimbatore']);
  });

  it('serves Singapore from the SG-SG city-state exception', async () => {
    const service = buildService();
    const states = await service.listSubdivisions('SG');
    expect(states).toHaveLength(1);
    expect(states[0]).toMatchObject({ code: 'SG-SG', type: 'City-state' });
    expect((await service.listCities('SG-SG')).map((c) => c.code)).toEqual(['SG-SG-SINGAPORE']);
  });

  it('serves a repeated read from memory without re-querying', async () => {
    const service = buildService();
    const cities = queryOf(service, 'city');

    await service.listCities('IN-TN');
    expect(cities).toHaveBeenCalledTimes(1);

    await service.listCities('IN-TN');
    await service.listCities('IN-TN');
    expect(cities).toHaveBeenCalledTimes(1);
  });

  it('collapses concurrent first-time reads into a single query', async () => {
    // Three dropdowns opening at once used to fire three separate full
    // loads, because the guard was `if (!loaded) await load()` with nothing
    // tracking the request already in flight.
    const service = buildService();
    const cities = queryOf(service, 'city');

    const results = await Promise.all([
      service.listCities('IN-TN'),
      service.listCities('IN-TN'),
      service.listCities('IN-TN'),
    ]);

    expect(cities).toHaveBeenCalledTimes(1);
    expect(results[0]).toEqual(results[1]);
    expect(results[1]).toEqual(results[2]);
  });

  it('never asks the database for more than one subdivision of cities', async () => {
    const service = buildService();
    const cities = queryOf(service, 'city');

    await service.listCities('IN-TN');
    await service.listCities('IN-KL', { search: 'ko' });

    // The regression this guards: loading the whole city table. Every call
    // must be scoped to one subdivision and bounded by a limit.
    for (const [args] of cities.mock.calls) {
      expect(args.where.stateCode).toBeDefined();
      expect(args.take).toBeGreaterThan(0);
    }
  });

  it('selects only the columns the UI renders', async () => {
    const service = buildService();
    await service.listCities('IN-TN');
    await service.listCountries();

    // population/isActive/createdAt/updatedAt were half the bytes on the
    // wire and nothing renders them.
    const [cityArgs] = queryOf(service, 'city').mock.calls[0];
    expect(Object.keys(cityArgs.select).sort()).toEqual([
      'code',
      'countryCode',
      'label',
      'stateCode',
    ]);
    const [countryArgs] = queryOf(service, 'country').mock.calls[0];
    expect(Object.keys(countryArgs.select).sort()).toEqual(['code', 'label']);
  });

  it('does not memoise an empty result', async () => {
    // An empty list is far more likely to be an unseeded database than a
    // real answer; caching it would leave the dropdown empty until the next
    // deploy.
    const service = buildService();
    const cities = queryOf(service, 'city');

    // IN-DD exists but its only city is inactive, so the active-only query
    // comes back empty.
    expect(await service.listCities('IN-DD')).toEqual([]);
    await service.listCities('IN-DD');
    expect(cities).toHaveBeenCalledTimes(2);
  });
});

describe('LocationService.resolve', () => {
  it('returns null when no codes are supplied, so legacy clients still save', async () => {
    const service = buildService();
    await expect(service.resolve({})).resolves.toBeNull();
    await expect(
      service.resolve({ countryCode: null, stateCode: null, cityCode: null }),
    ).resolves.toBeNull();
  });

  it('resolves a valid triple to its canonical codes and labels', async () => {
    const service = buildService();
    await expect(
      service.resolve({ countryCode: 'IN', stateCode: 'IN-TN', cityCode: 'IN-TN-CHENNAI' }),
    ).resolves.toEqual({
      countryCode: 'IN',
      stateCode: 'IN-TN',
      cityCode: 'IN-TN-CHENNAI',
      countryLabel: 'India',
      stateLabel: 'Tamil Nadu',
      cityLabel: 'Chennai',
    });
  });

  it('accepts lowercase codes — clients should not have to care about case', async () => {
    const service = buildService();
    const resolved = await service.resolve({
      countryCode: 'in',
      stateCode: 'in-tn',
      cityCode: 'in-tn-chennai',
    });
    expect(resolved?.cityCode).toBe('IN-TN-CHENNAI');
  });

  it('refuses a city that is not in the stated state', async () => {
    const service = buildService();
    // This is the whole point of server-side validation: a hand-crafted
    // request cannot file Kochi under Tamil Nadu.
    await expect(
      service.resolve({ countryCode: 'IN', stateCode: 'IN-TN', cityCode: 'IN-KL-KOCHI' }),
    ).rejects.toThrow(/not in Tamil Nadu/);
  });

  it('refuses a state that is not in the stated country', async () => {
    const service = buildService();
    await expect(
      service.resolve({ countryCode: 'SG', stateCode: 'IN-TN' }),
    ).rejects.toThrow(/not in Singapore/);
  });

  it('refuses a city without its parent state', async () => {
    const service = buildService();
    await expect(
      service.resolve({ countryCode: 'IN', cityCode: 'IN-TN-CHENNAI' }),
    ).rejects.toThrow(/must be accompanied by its state code/);
  });

  it('refuses a state without its parent country', async () => {
    const service = buildService();
    await expect(service.resolve({ stateCode: 'IN-TN' })).rejects.toThrow(
      /must be accompanied by its country code/,
    );
  });

  it('refuses codes that name nothing', async () => {
    const service = buildService();
    await expect(service.resolve({ countryCode: 'ZZ' })).rejects.toThrow(/Unknown country/);
    await expect(
      service.resolve({ countryCode: 'IN', stateCode: 'IN-ZZ' }),
    ).rejects.toThrow(/Unknown state/);
    await expect(
      service.resolve({ countryCode: 'IN', stateCode: 'IN-TN', cityCode: 'IN-TN-NOWHERE' }),
    ).rejects.toThrow(/Unknown city/);
  });

  it('still resolves a retired code, so an existing member can save other edits', async () => {
    const service = buildService();
    // IN-DD is inactive and absent from every dropdown, but a profile saved
    // before it was retired still holds it. Refusing it here would force that
    // member to re-answer where they live before they could change anything
    // else about their profile.
    await expect(
      service.resolve({ countryCode: 'IN', stateCode: 'IN-DD', cityCode: 'IN-DD-DAMAN' }),
    ).resolves.toMatchObject({ stateCode: 'IN-DD', stateLabel: 'Daman and Diu' });
  });
});
