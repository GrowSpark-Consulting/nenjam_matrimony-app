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

function buildService(): LocationService {
  // The mock sorts the way the real queries' `orderBy` clauses do, so these
  // tests exercise the service's own ordering rather than fixture order.
  const byLabel = <T extends { label: string }>(rows: T[]) =>
    [...rows].sort((a, b) => a.label.localeCompare(b.label));
  const prisma = {
    country: { findMany: jest.fn().mockResolvedValue(byLabel(COUNTRIES)) },
    subdivision: { findMany: jest.fn().mockResolvedValue(byLabel(SUBDIVISIONS)) },
    city: {
      findMany: jest.fn().mockResolvedValue(
        [...CITIES].sort((a, b) => b.population - a.population || a.label.localeCompare(b.label)),
      ),
    },
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

  it('loads the dataset once, however many reads follow', async () => {
    const service = buildService();
    await service.listCountries();
    await service.listCountries();
    await service.listCities('IN-TN');
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const findMany = (service as any).prisma.country.findMany as jest.Mock;
    expect(findMany).toHaveBeenCalledTimes(1);
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
