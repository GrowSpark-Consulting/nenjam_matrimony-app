import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type { CityDto, CountryDto, SubdivisionDto } from '../dto/location.response.dto';

/**
 * The authority on locations, for both reads and writes.
 *
 * ## Why this is lazy rather than preloaded
 *
 * The first version loaded the whole dataset at boot in `onModuleInit`. That
 * was measurably wrong: 9,700 rows and ~1.84 MB from Neon in Singapore took
 * **4.1 seconds**, and because Nest awaits `onModuleInit` before it starts
 * listening, the container served *nothing* until it finished. On a platform
 * that idles containers, every member who opened the location step after a
 * quiet period paid that 4.1s.
 *
 * The measurements that settled it:
 *
 * | | rows | wire | time |
 * |---|---|---|---|
 * | whole hierarchy, all 8 columns | 9,700 | 1.84 MB | 4,130 ms |
 * | countries, 2 columns | 8 | <1 KB | ~0.05 ms in PG |
 * | states for one country, 4 columns | 35 | 2.5 KB | ~0.05 ms in PG |
 * | cities for one state, 4 columns, limit 50 | 50 | 4.2 KB | ~0.16 ms in PG |
 *
 * Every targeted query is sub-millisecond in Postgres and uses its index
 * (verified with EXPLAIN ANALYZE). The old approach paid seconds up front to
 * save a query that costs a fraction of a millisecond.
 *
 * ## What replaced it
 *
 * Each list is fetched on demand, selecting only the columns the UI renders,
 * and memoised per cache key. Countries and subdivisions are static between
 * deploys, so the first caller warms them and everyone after is served from
 * memory with no database round trip at all.
 *
 * Redis is deliberately not used. This is per-process memoisation of a small,
 * public, deploy-static table; adding an infrastructure dependency for it
 * would cost a network hop to save a sub-millisecond query.
 */
@Injectable()
export class LocationService {
  private readonly logger = new Logger(LocationService.name);

  /** Only what the DTOs expose. Not `createdAt`/`updatedAt`/`population` —
   *  those were half the bytes on the wire and nothing renders them. */
  private static readonly COUNTRY_COLUMNS = { code: true, label: true } as const;
  private static readonly SUBDIVISION_COLUMNS = {
    code: true,
    label: true,
    type: true,
    countryCode: true,
  } as const;
  private static readonly CITY_COLUMNS = {
    code: true,
    label: true,
    stateCode: true,
    countryCode: true,
  } as const;

  /** Memoised list results, keyed by the query that produced them. */
  private readonly lists = new Map<string, unknown[]>();

  /**
   * Requests already in flight, so N concurrent callers for the same key
   * issue ONE query rather than N.
   *
   * The previous `if (!loaded) await load()` had no such guard: three
   * dropdowns opening together fired three full 1.84 MB loads.
   */
  private readonly inFlight = new Map<string, Promise<unknown[]>>();

  /** Single rows already looked up by primary key, so a repeated validation
   *  costs nothing. `null` is a real cached answer meaning "no such code". */
  private readonly rows = new Map<string, unknown>();
  private readonly rowsInFlight = new Map<string, Promise<unknown>>();

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Fetch-once-per-key with in-flight deduplication.
   *
   * Note there is no TTL. The data changes only when `pnpm seed:locations`
   * runs during a deploy, and a deploy restarts the process, so an expiry
   * would only ever throw away a still-correct answer.
   */
  private async memoise<T>(key: string, fetch: () => Promise<T[]>): Promise<T[]> {
    const cached = this.lists.get(key);
    if (cached) return cached as T[];

    const pending = this.inFlight.get(key);
    if (pending) return pending as Promise<T[]>;

    const startedAt = Date.now();
    const request = fetch()
      .then((rows) => {
        // Only a non-empty result is memoised. An empty list is far more
        // likely to be an unseeded database than a real answer, and caching
        // it would keep the dropdown empty until the next deploy.
        if (rows.length > 0) this.lists.set(key, rows);
        // One line per cache key per process. Enough to tell "the database is
        // slow" from "the cache is not being hit" from production logs alone,
        // which is the question that started this whole investigation.
        this.logger.log(
          `${key} filled from database in ${Date.now() - startedAt}ms (${rows.length} rows)` +
            (rows.length === 0 ? ' — empty, NOT cached; is the seed present?' : ''),
        );
        return rows;
      })
      .finally(() => this.inFlight.delete(key));

    this.inFlight.set(key, request as Promise<unknown[]>);
    return request;
  }

  // ── Reads ───────────────────────────────────────────────────────────────

  async listCountries(includeInactive = false): Promise<CountryDto[]> {
    return this.memoise(`countries:${includeInactive}`, () =>
      this.prisma.country.findMany({
        where: includeInactive ? undefined : { isActive: true },
        select: LocationService.COUNTRY_COLUMNS,
        orderBy: { label: 'asc' },
      }),
    );
  }

  async listSubdivisions(
    countryCode: string,
    includeInactive = false,
  ): Promise<SubdivisionDto[]> {
    // Reject an unknown country rather than returning []. An empty array
    // would read to the client as "this country has no states", which is a
    // very different thing from "no such country".
    await this.assertCountryExists(countryCode);

    return this.memoise(`states:${countryCode}:${includeInactive}`, () =>
      this.prisma.subdivision.findMany({
        where: {
          countryCode,
          ...(includeInactive ? {} : { isActive: true }),
        },
        select: LocationService.SUBDIVISION_COLUMNS,
        orderBy: { label: 'asc' },
      }),
    );
  }

  /**
   * Cities for one subdivision — never for a country, and never all of them.
   *
   * `search` is applied in Postgres, not in Node, so a search never has to
   * load the whole subdivision first. Ordering is largest-first so a page
   * without a search term still shows the cities members actually live in.
   */
  async listCities(
    stateCode: string,
    options: { search?: string; limit?: number; offset?: number } = {},
  ): Promise<CityDto[]> {
    await this.assertSubdivisionExists(stateCode);

    const limit = Math.min(Math.max(options.limit ?? 200, 1), 1000);
    const offset = Math.max(options.offset ?? 0, 0);
    const search = options.search?.trim();

    const where = {
      stateCode,
      isActive: true,
      ...(search ? { label: { contains: search, mode: 'insensitive' as const } } : {}),
    };

    // An unfiltered page is the common case (opening the dropdown) and is
    // memoised. A search is not: the key space is every prefix a member
    // might type, which would grow without bound for no benefit — the query
    // itself is sub-millisecond and index-backed.
    const fetch = () =>
      this.prisma.city.findMany({
        where,
        select: LocationService.CITY_COLUMNS,
        orderBy: [{ population: 'desc' }, { label: 'asc' }],
        take: limit,
        skip: offset,
      });

    const rows = search
      ? await fetch()
      : await this.memoise(`cities:${stateCode}:${limit}:${offset}`, fetch);

    if (!search) return rows;

    // Rank prefix matches above substring matches. Postgres has already cut
    // this to at most `limit` rows, so the sort is over a page, not a table.
    // Someone typing "cast" in New South Wales means Castle Hill, even though
    // Newcastle is 13x larger.
    const query = search.toLowerCase();
    const starts: CityDto[] = [];
    const contains: CityDto[] = [];
    for (const city of rows) {
      (city.label.toLowerCase().startsWith(query) ? starts : contains).push(city);
    }
    return [...starts, ...contains];
  }

  // ── Existence checks ────────────────────────────────────────────────────

  /**
   * One row by primary key, memoised — including a `null` result, which is a
   * real answer meaning "no such code".
   *
   * This replaced loading all 8 countries and all 384 subdivisions to check
   * whether one code existed. That cost **1,755 ms** on the first `states`
   * request; a primary-key lookup is one indexed row and a single round trip,
   * and after the first call it is free.
   *
   * Lookups deliberately ignore `isActive`: a member holding a since-retired
   * code must still be able to save an unrelated edit. Only the list
   * endpoints filter on it.
   */
  private async findRow<T>(key: string, fetch: () => Promise<T | null>): Promise<T | null> {
    if (this.rows.has(key)) return this.rows.get(key) as T | null;

    const pending = this.rowsInFlight.get(key);
    if (pending) return pending as Promise<T | null>;

    const request = fetch()
      .then((row) => {
        this.rows.set(key, row);
        return row;
      })
      .finally(() => this.rowsInFlight.delete(key));

    this.rowsInFlight.set(key, request as Promise<unknown>);
    return request;
  }

  private findCountry(code: string) {
    return this.findRow(`country:${code}`, () =>
      this.prisma.country.findUnique({
        where: { code },
        select: LocationService.COUNTRY_COLUMNS,
      }),
    );
  }

  private findSubdivision(code: string) {
    return this.findRow(`state:${code}`, () =>
      this.prisma.subdivision.findUnique({
        where: { code },
        select: { code: true, label: true, countryCode: true },
      }),
    );
  }

  private findCity(code: string) {
    return this.findRow(`city:${code}`, () =>
      this.prisma.city.findUnique({
        where: { code },
        select: LocationService.CITY_COLUMNS,
      }),
    );
  }

  private async assertCountryExists(code: string): Promise<void> {
    if (!(await this.findCountry(code))) {
      throw new NotFoundException(`Unknown country code "${code}".`);
    }
  }

  private async assertSubdivisionExists(code: string): Promise<void> {
    if (!(await this.findSubdivision(code))) {
      throw new NotFoundException(`Unknown subdivision code "${code}".`);
    }
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

    // Three primary-key lookups, issued together rather than one after the
    // other: a profile save waits for one round trip, not three. Each is
    // memoised, so a second save of the same location costs nothing.
    const [country, state, city] = await Promise.all([
      countryCode ? this.findCountry(countryCode) : null,
      stateCode ? this.findSubdivision(stateCode) : null,
      cityCode ? this.findCity(cityCode) : null,
    ]);

    if (countryCode && !country) {
      throw new NotFoundException(`Unknown country code "${countryCode}".`);
    }

    if (stateCode && !state) {
      throw new NotFoundException(`Unknown state code "${stateCode}".`);
    }
    if (state && country && state.countryCode !== country.code) {
      throw new NotFoundException(
        `"${state.label}" is not in ${country.label} — it is in ${state.countryCode}.`,
      );
    }

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
