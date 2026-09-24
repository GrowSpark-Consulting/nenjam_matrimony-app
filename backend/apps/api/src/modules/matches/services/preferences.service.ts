import { Injectable } from '@nestjs/common';
import { FeedInvalidationService } from '../cache/feed-invalidation.service';
import { PreferenceRepository } from '../repositories/preference.repository';
import type { PartnerPreferenceRow } from '../repositories/preference.repository';
import {
  PartnerPreferenceResponseDto,
  UpdatePartnerPreferenceDto,
} from '../dto/partner-preference.dto';

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
    private readonly feedInvalidation: FeedInvalidationService,
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

    // The one field whose wire name differs from its column: the client sends
    // `extended`, the row stores `extended_preferences`. Same partial rule as
    // everything above — supplied replaces the blob, omitted leaves it alone.
    if (dto.extended !== undefined) {
      data.extendedPreferences = dto.extended;
    }

    const row = await this.preferenceRepository.upsert(userId, data as never);

    // Preferences are half of the cached feed context, so the next feed
    // request must not be served the old ones. Runs only AFTER the write
    // succeeds — dropping the key before would let a concurrent request
    // repopulate it from the pre-update row. Also bumps the feed version and
    // pushes feed.invalidate so an open client refreshes immediately.
    await this.feedInvalidation.invalidate(userId, 'preferences_updated');

    return this.toDto(row);
  }

  private toDto(
    row: PartnerPreferenceRow | null,
  ): PartnerPreferenceResponseDto {
    return {
      // Null stays null: "no limit". Filling in 18-45 / 140-210 here would
      // hand the client a range the member never chose, which the next Save
      // would then write back as a real restriction.
      minAge: row?.minAge ?? null,
      maxAge: row?.maxAge ?? null,
      minHeightCm: row?.minHeightCm ?? null,
      maxHeightCm: row?.maxHeightCm ?? null,
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
      extended: asRecord(row?.extendedPreferences),
    };
  }
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((v): v is string => typeof v === 'string');
}

/** The stored JSON blob, or `{}` for a member who has never saved one. A
 *  non-object (legacy row, hand-edited value) reads as empty rather than
 *  being handed to the client as something it cannot use. */
function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}
