import { Injectable } from '@nestjs/common';
import { RedisService } from '@app/cache';
import { invalidateFeedContext } from '../cache/feed-context.cache';
import { PreferenceRepository } from '../repositories/preference.repository';
import type { PartnerPreferenceRow } from '../repositories/preference.repository';
import {
  PartnerPreferenceResponseDto,
  UpdatePartnerPreferenceDto,
} from '../dto/partner-preference.dto';

// Schema defaults (partner_preferences) — returned by GET before a user has
// saved anything, so the client always renders a complete, sensible form.
const DEFAULTS = {
  minAge: 18,
  maxAge: 45,
  minHeightCm: 140,
  maxHeightCm: 210,
} as const;

/**
 * The single source of truth for a user's partner preferences. The
 * registration wizard may seed them at finalize, but every later read/edit
 * flows through here (GET/PUT /discover/preferences), and the feed filter
 * reads the exact same row.
 */
@Injectable()
export class PreferencesService {
  constructor(
    private readonly preferenceRepository: PreferenceRepository,
    private readonly redis: RedisService,
  ) {}

  async get(userId: string): Promise<PartnerPreferenceResponseDto> {
    const row = await this.preferenceRepository.findByUserId(userId);
    return this.toDto(row);
  }

  async update(
    userId: string,
    dto: UpdatePartnerPreferenceDto,
  ): Promise<PartnerPreferenceResponseDto> {
    // Only send through the keys the caller actually provided, so a partial
    // PUT never clobbers unrelated fields with undefined.
    const data: Record<string, unknown> = {};
    const assign = (key: keyof UpdatePartnerPreferenceDto) => {
      if (dto[key] !== undefined) data[key] = dto[key];
    };
    (
      [
        'minAge',
        'maxAge',
        'minHeightCm',
        'maxHeightCm',
        'minIncomeLakhs',
        'preferredReligions',
        'preferredCastes',
        'preferredMotherTongues',
        'preferredEducation',
        'preferredOccupations',
        'preferredCities',
        'preferredStates',
        'maritalStatusPref',
      ] as Array<keyof UpdatePartnerPreferenceDto>
    ).forEach(assign);

    const row = await this.preferenceRepository.upsert(userId, data as never);

    // Preferences are half of the cached feed context, so the next feed
    // request must not be served the old ones. Invalidated only AFTER the
    // write succeeds — dropping the key before would let a concurrent request
    // repopulate it from the pre-update row.
    await invalidateFeedContext(this.redis, userId);

    return this.toDto(row);
  }

  private toDto(
    row: PartnerPreferenceRow | null,
  ): PartnerPreferenceResponseDto {
    return {
      minAge: row?.minAge ?? DEFAULTS.minAge,
      maxAge: row?.maxAge ?? DEFAULTS.maxAge,
      minHeightCm: row?.minHeightCm ?? DEFAULTS.minHeightCm,
      maxHeightCm: row?.maxHeightCm ?? DEFAULTS.maxHeightCm,
      minIncomeLakhs:
        row?.minIncomeLakhs != null ? Number(row.minIncomeLakhs) : null,
      preferredReligions: asStringArray(row?.preferredReligions),
      preferredCastes: asStringArray(row?.preferredCastes),
      preferredMotherTongues: asStringArray(row?.preferredMotherTongues),
      preferredEducation: asStringArray(row?.preferredEducation),
      preferredOccupations: asStringArray(row?.preferredOccupations),
      preferredCities: asStringArray(row?.preferredCities),
      preferredStates: asStringArray(row?.preferredStates),
      maritalStatusPref: asStringArray(row?.maritalStatusPref),
    };
  }
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((v): v is string => typeof v === 'string');
}
