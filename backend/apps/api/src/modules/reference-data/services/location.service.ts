import { Injectable, Logger, NotFoundException, OnModuleInit } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type { CityDto, CountryDto, SubdivisionDto } from '../dto/location.response.dto';

/**
 * The authority on locations, for both reads and writes.
 *
 * The whole dataset — 8 countries, 384 subdivisions, ~9,300 cities — is held
 * in memory. It is roughly half a megabyte, it is identical on every instance,
 * and it changes only when `pnpm seed:locations` runs during a deploy, so
 * paying a network round trip to Neon in Singapore for each dropdown would buy
 * nothing. Redis is not used for the same reason, and because it is an
 * optional dependency in development while registration is not.
 *
 * The trade is that a seed run mid-process is not picked up until restart.
 * That is the correct trade here: deploys restart the process anyway.
 */
@Injectable()
export class LocationService implements OnModuleInit {
  private readonly logger = new Logger(LocationService.name);

  private countries: CountryDto[] = [];
  private subdivisions: SubdivisionDto[] = [];
  /** All rows, active and inactive, so a legacy code still resolves. */
  private countryByCode = new Map<string, CountryDto & { isActive: boolean }>();
  private subdivisionByCode = new Map<string, SubdivisionDto & { isActive: boolean }>();
  private cityByCode = new Map<string, CityDto & { isActive: boolean }>();
  /** Active cities per subdivision, pre-sorted largest first. */
  private citiesByState = new Map<string, CityDto[]>();
  private loaded = false;

  constructor(private readonly prisma: PrismaService) {}

  async onModuleInit(): Promise<void> {
    // Warm at boot so the first member to open the location step doesn't pay
    // for it. A failure here must not stop the API: every other feature works
    // without location data, and the endpoints below report the outage
    // honestly rather than serving a silently empty list.
    try {
      await this.load();
    } catch (error) {
      this.logger.error(
        `Location master data could not be loaded at startup; ` +
          `location endpoints will retry on first use. ` +
          `Has \`pnpm seed:locations\` been run? ${(error as Error).message}`,
      );
    }
  }

  private async load(): Promise<void> {
    const [countries, subdivisions, cities] = await Promise.all([
      this.prisma.country.findMany({ orderBy: { label: 'asc' } }),
      this.prisma.subdivision.findMany({ orderBy: { label: 'asc' } }),
      // Largest first, then alphabetical: members expect their own large city
      // near the top of the list, not buried under alphabetical neighbours.
      this.prisma.city.findMany({
        orderBy: [{ population: 'desc' }, { label: 'asc' }],
      }),
    ]);

    this.countryByCode = new Map(
      countries.map((c) => [c.code, { code: c.code, label: c.label, isActive: c.isActive }]),
    );
    this.subdivisionByCode = new Map(
      subdivisions.map((s) => [
        s.code,
        {
          code: s.code,
          label: s.label,
          type: s.type,
          countryCode: s.countryCode,
          isActive: s.isActive,
        },
      ]),
    );
    this.cityByCode = new Map(
      cities.map((c) => [
        c.code,
        {
          code: c.code,
          label: c.label,
          stateCode: c.stateCode,
          countryCode: c.countryCode,
          isActive: c.isActive,
        },
      ]),
    );

    this.countries = countries
      .filter((c) => c.isActive)
      .map((c) => ({ code: c.code, label: c.label }));
    this.subdivisions = subdivisions
      .filter((s) => s.isActive)
      .map((s) => ({ code: s.code, label: s.label, type: s.type, countryCode: s.countryCode }));

    this.citiesByState = new Map();
    for (const city of cities) {
      if (!city.isActive) continue;
      const bucket = this.citiesByState.get(city.stateCode);
      const dto: CityDto = {
        code: city.code,
        label: city.label,
        stateCode: city.stateCode,
        countryCode: city.countryCode,
      };
      if (bucket) bucket.push(dto);
      else this.citiesByState.set(city.stateCode, [dto]);
    }

    this.loaded = true;
    this.logger.log(
      `Location master data loaded: ${this.countries.length} countries, ` +
        `${this.subdivisions.length} subdivisions, ${this.citiesByState.size} populated ` +
        `subdivisions, ${cities.length} cities.`,
    );
  }

  private async ensureLoaded(): Promise<void> {
    if (!this.loaded) await this.load();
  }

  // ── Reads ───────────────────────────────────────────────────────────────

  async listCountries(includeInactive = false): Promise<CountryDto[]> {
    await this.ensureLoaded();
    if (!includeInactive) return this.countries;
    return [...this.countryByCode.values()]
      .map(({ code, label }) => ({ code, label }))
      .sort((a, b) => a.label.localeCompare(b.label));
  }

  async listSubdivisions(countryCode: string, includeInactive = false): Promise<SubdivisionDto[]> {
    await this.ensureLoaded();
    const country = this.countryByCode.get(countryCode);
    if (!country) {
      throw new NotFoundException(`Unknown country code "${countryCode}".`);
    }
    const source = includeInactive
      ? [...this.subdivisionByCode.values()]
      : this.subdivisions;
    return source
      .filter((s) => s.countryCode === countryCode)
      .map(({ code, label, type, countryCode: cc }) => ({ code, label, type, countryCode: cc }))
      .sort((a, b) => a.label.localeCompare(b.label));
  }

  async listCities(
    stateCode: string,
    options: { search?: string; limit?: number } = {},
  ): Promise<CityDto[]> {
    await this.ensureLoaded();
    const subdivision = this.subdivisionByCode.get(stateCode);
    if (!subdivision) {
      throw new NotFoundException(`Unknown subdivision code "${stateCode}".`);
    }

    // Already sorted largest-first at load time, so a limit takes the biggest
    // cities rather than an arbitrary slice.
    let cities = this.citiesByState.get(stateCode) ?? [];
    const search = options.search?.trim().toLowerCase();
    if (search) {
      const starts = cities.filter((c) => c.label.toLowerCase().startsWith(search));
      const contains = cities.filter(
        (c) => !c.label.toLowerCase().startsWith(search) && c.label.toLowerCase().includes(search),
      );
      // Prefix matches first: someone typing "chen" means Chennai, not
      // Kanchipuram, even though both contain the letters.
      cities = [...starts, ...contains];
    }
    return cities.slice(0, options.limit ?? 200);
  }

  // ── Validation, used by profile and preference writes ───────────────────

  /**
   * Confirms a country/state/city triple exists and that the hierarchy is
   * genuinely consistent — the city really is in that state, and the state
   * really is in that country. This is why the server, not the client, is the
   * authority: a hand-crafted request cannot file Chennai under Singapore.
   *
   * Codes are matched against ALL rows, active and inactive. An existing
   * member whose profile holds a since-retired code must still be able to save
   * an unrelated edit without being forced to re-answer where they live; only
   * the dropdowns filter on `isActive`.
   *
   * Returns the resolved labels so the caller can store both code and text.
   */
  async resolve(input: {
    countryCode?: string | null;
    stateCode?: string | null;
    cityCode?: string | null;
  }): Promise<{
    countryCode: string | null;
    stateCode: string | null;
    cityCode: string | null;
    countryLabel: string | null;
    stateLabel: string | null;
    cityLabel: string | null;
  } | null> {
    const countryCode = input.countryCode?.trim().toUpperCase() || null;
    const stateCode = input.stateCode?.trim().toUpperCase() || null;
    const cityCode = input.cityCode?.trim().toUpperCase() || null;

    // Nothing supplied is not an error: structured location is optional, and
    // every profile written before this feature existed has none.
    if (!countryCode && !stateCode && !cityCode) return null;

    await this.ensureLoaded();

    const country = countryCode ? this.countryByCode.get(countryCode) : null;
    if (countryCode && !country) {
      throw new NotFoundException(`Unknown country code "${countryCode}".`);
    }

    const state = stateCode ? this.subdivisionByCode.get(stateCode) : null;
    if (stateCode && !state) {
      throw new NotFoundException(`Unknown state code "${stateCode}".`);
    }
    if (state && country && state.countryCode !== country.code) {
      throw new NotFoundException(
        `"${state.label}" is not in ${country.label} — it is in ${state.countryCode}.`,
      );
    }

    const city = cityCode ? this.cityByCode.get(cityCode) : null;
    if (cityCode && !city) {
      throw new NotFoundException(`Unknown city code "${cityCode}".`);
    }
    if (city && state && city.stateCode !== state.code) {
      throw new NotFoundException(
        `"${city.label}" is not in ${state.label} — it is in ${city.stateCode}.`,
      );
    }
    if (city && country && city.countryCode !== country.code) {
      throw new NotFoundException(
        `"${city.label}" is not in ${country.label} — it is in ${city.countryCode}.`,
      );
    }
    // A city without its state is ambiguous to store and impossible to render
    // as a hierarchy, so require the parent rather than inferring it.
    if (city && !state) {
      throw new NotFoundException('A city code must be accompanied by its state code.');
    }
    if (state && !country) {
      throw new NotFoundException('A state code must be accompanied by its country code.');
    }

    return {
      countryCode: country?.code ?? null,
      stateCode: state?.code ?? null,
      cityCode: city?.code ?? null,
      countryLabel: country?.label ?? null,
      stateLabel: state?.label ?? null,
      cityLabel: city?.label ?? null,
    };
  }
}
