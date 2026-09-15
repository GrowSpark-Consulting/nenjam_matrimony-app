import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type { CommunityDto, ReligionDto } from '../dto/religion.response.dto';

/**
 * Religion -> Community reference data.
 *
 * Lazy and memoised for the same reasons LocationService is — see that file
 * for the measurements. Nothing is loaded at boot: `onModuleInit` there cost
 * 4.1s of blocked startup, and this dataset would sit on the same path.
 *
 * It is far smaller than the location tables (7 religions, ~60 communities),
 * so a single query per key is cheap and the whole thing ends up in memory
 * after the first caller touches each level anyway.
 */
@Injectable()
export class ReligionService {
  private readonly logger = new Logger(ReligionService.name);

  /** Only what the DTOs expose — not createdAt/updatedAt/isActive. */
  private static readonly RELIGION_COLUMNS = { code: true, label: true } as const;
  private static readonly COMMUNITY_COLUMNS = {
    code: true,
    label: true,
    religionCode: true,
  } as const;

  private readonly lists = new Map<string, unknown[]>();
  /** Requests already running, so N concurrent callers issue ONE query. */
  private readonly inFlight = new Map<string, Promise<unknown[]>>();
  private readonly rows = new Map<string, unknown>();

  constructor(private readonly prisma: PrismaService) {}

  private async memoise<T>(key: string, fetch: () => Promise<T[]>): Promise<T[]> {
    const cached = this.lists.get(key);
    if (cached) return cached as T[];

    const pending = this.inFlight.get(key);
    if (pending) return pending as Promise<T[]>;

    const startedAt = Date.now();
    const request = fetch()
      .then((rows) => {
        // An empty list is far more likely to be an unseeded database than a
        // real answer, so it is never cached — otherwise the dropdown would
        // stay empty until the next deploy.
        if (rows.length > 0) this.lists.set(key, rows);
        this.logger.log(
          `${key} filled from database in ${Date.now() - startedAt}ms (${rows.length} rows)` +
            (rows.length === 0 ? ' — empty, NOT cached; has seed:religions run?' : ''),
        );
        return rows;
      })
      .finally(() => this.inFlight.delete(key));

    this.inFlight.set(key, request as Promise<unknown[]>);
    return request;
  }

  // ── Reads ───────────────────────────────────────────────────────────────

  async listReligions(includeInactive = false): Promise<ReligionDto[]> {
    return this.memoise(`religions:${includeInactive}`, () =>
      this.prisma.religion.findMany({
        where: includeInactive ? undefined : { isActive: true },
        select: ReligionService.RELIGION_COLUMNS,
        orderBy: { label: 'asc' },
      }),
    );
  }

  /**
   * Communities within one religion — never all of them.
   *
   * An unknown religion is a 404 rather than `[]`: an empty array reads to the
   * client as "this religion has no communities", which is a very different
   * thing from "no such religion". A religion that genuinely has none is a
   * real, empty answer.
   */
  async listCommunities(
    religionCode: string,
    includeInactive = false,
  ): Promise<CommunityDto[]> {
    await this.assertReligionExists(religionCode);

    return this.memoise(`communities:${religionCode}:${includeInactive}`, () =>
      this.prisma.community.findMany({
        where: {
          religionCode,
          ...(includeInactive ? {} : { isActive: true }),
        },
        select: ReligionService.COMMUNITY_COLUMNS,
        orderBy: { label: 'asc' },
      }),
    );
  }

  // ── Existence / validation ──────────────────────────────────────────────

  private async findRow<T>(key: string, fetch: () => Promise<T | null>): Promise<T | null> {
    if (this.rows.has(key)) return this.rows.get(key) as T | null;
    const row = await fetch();
    // `null` is cached too — it is a real answer meaning "no such code".
    this.rows.set(key, row);
    return row;
  }

  /** Lookups ignore `isActive`: a member holding a since-retired code must
   *  still be able to save an unrelated edit. Only lists filter on it. */
  private findReligion(code: string) {
    return this.findRow(`religion:${code}`, () =>
      this.prisma.religion.findUnique({
        where: { code },
        select: ReligionService.RELIGION_COLUMNS,
      }),
    );
  }

  private findCommunity(code: string) {
    return this.findRow(`community:${code}`, () =>
      this.prisma.community.findUnique({
        where: { code },
        select: ReligionService.COMMUNITY_COLUMNS,
      }),
    );
  }

  private async assertReligionExists(code: string): Promise<void> {
    if (!(await this.findReligion(code))) {
      throw new NotFoundException(`Unknown religion code "${code}".`);
    }
  }

  /**
   * Confirms a religion/community pair exists and that the community really
   * belongs to that religion — so a hand-crafted request cannot file a
   * Jain community under Islam.
   *
   * Returns the resolved labels, so the caller can keep writing the existing
   * free-text `religion` / `community` columns from the master data and the
   * two can never disagree. Null when no codes were supplied, which is every
   * profile written before this existed.
   */
  async resolve(input: {
    religionCode?: string | null;
    communityCode?: string | null;
  }): Promise<{
    religionCode: string | null;
    communityCode: string | null;
    religionLabel: string | null;
    communityLabel: string | null;
  } | null> {
    const religionCode = input.religionCode?.trim().toUpperCase() || null;
    const communityCode = input.communityCode?.trim().toUpperCase() || null;
    if (!religionCode && !communityCode) return null;

    const [religion, community] = await Promise.all([
      religionCode ? this.findReligion(religionCode) : null,
      communityCode ? this.findCommunity(communityCode) : null,
    ]);

    if (religionCode && !religion) {
      throw new NotFoundException(`Unknown religion code "${religionCode}".`);
    }
    if (communityCode && !community) {
      throw new NotFoundException(`Unknown community code "${communityCode}".`);
    }
    if (community && religion && community.religionCode !== religion.code) {
      throw new NotFoundException(
        `"${community.label}" is not a ${religion.label} community — ` +
          `it belongs to ${community.religionCode}.`,
      );
    }
    if (community && !religion) {
      throw new NotFoundException(
        'A community code must be accompanied by its religion code.',
      );
    }

    return {
      religionCode: religion?.code ?? null,
      communityCode: community?.code ?? null,
      religionLabel: religion?.label ?? null,
      communityLabel: community?.label ?? null,
    };
  }
}
