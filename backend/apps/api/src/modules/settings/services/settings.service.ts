import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import {
  PrivacySettings,
  SettingsRepository,
} from '../repositories/settings.repository';
import { UpdatePrivacyDto } from '../dto/update-privacy.dto';

/** Prisma "record to update not found" — the user row was deleted between the
 *  auth guard resolving the id and this write. */
function isRecordNotFound(error: unknown): boolean {
  return (error as { code?: string })?.code === 'P2025';
}

/**
 * User settings business logic. The caller is always identified by the id the
 * auth guard resolved from the verified Firebase token, so every operation is
 * implicitly scoped to — and can only affect — that user's own row. Reads carry
 * DB-backed defaults (both preferences default to `false`), and updates are
 * strictly partial: only the fields the caller supplied are written, so an
 * omitted preference always keeps its current value.
 */
@Injectable()
export class SettingsService {
  private readonly logger = new Logger(SettingsService.name);

  constructor(private readonly settingsRepository: SettingsRepository) {}

  /** The caller's current privacy settings. 404s if the user no longer exists. */
  async getPrivacySettings(userId: string): Promise<PrivacySettings> {
    const settings = await this.settingsRepository.findPrivacyByUserId(userId);
    if (!settings) {
      throw new NotFoundException('User not found.');
    }
    return settings;
  }

  /**
   * Applies a partial privacy update. Only the fields present in [dto] are
   * written; omitted fields are preserved. An empty patch is a no-op that simply
   * returns the current settings (no wasted write).
   */
  async updatePrivacySettings(
    userId: string,
    dto: UpdatePrivacyDto,
  ): Promise<PrivacySettings> {
    const data = this.pickSuppliedFields(dto);
    if (Object.keys(data).length === 0) {
      return this.getPrivacySettings(userId);
    }

    try {
      const updated = await this.settingsRepository.updatePrivacyByUserId(
        userId,
        data,
      );
      this.logger.log(
        `Privacy settings updated for user ${userId}: ${Object.keys(data).join(', ')}.`,
      );
      return updated;
    } catch (error) {
      if (isRecordNotFound(error)) {
        throw new NotFoundException('User not found.');
      }
      throw error;
    }
  }

  /** Narrows the DTO to exactly the fields the caller sent, so a `PATCH` never
   *  overwrites a preference the caller didn't mention. */
  private pickSuppliedFields(dto: UpdatePrivacyDto): Partial<PrivacySettings> {
    const data: Partial<PrivacySettings> = {};
    if (dto.profileVisibleToPremiumOnly !== undefined) {
      data.profileVisibleToPremiumOnly = dto.profileVisibleToPremiumOnly;
    }
    if (dto.hidePhotosFromNonConnections !== undefined) {
      data.hidePhotosFromNonConnections = dto.hidePhotosFromNonConnections;
    }
    return data;
  }
}
