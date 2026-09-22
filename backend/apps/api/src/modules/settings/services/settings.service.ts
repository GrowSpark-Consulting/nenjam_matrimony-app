import {
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import {
  PrivacySettings,
  SettingsRepository,
} from '../repositories/settings.repository';
import { UpdatePrivacyDto } from '../dto/update-privacy.dto';
import { PrivacySettingsResponse } from '../dto/privacy-settings.response.dto';
import { EntitlementService } from '../../entitlements/services/entitlement.service';

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
 *
 * Both privacy preferences are premium features. Premium is looked up once per
 * request from the caller's subscription rows (EntitlementService); the client
 * cannot assert it. Reads report the effective value (stored AND premium), and
 * switching a feature ON without premium is refused.
 */
@Injectable()
export class SettingsService {
  private readonly logger = new Logger(SettingsService.name);

  constructor(
    private readonly settingsRepository: SettingsRepository,
    private readonly entitlementService: EntitlementService,
  ) {}

  /** The caller's current privacy settings. 404s if the user no longer exists. */
  async getPrivacySettings(userId: string): Promise<PrivacySettingsResponse> {
    const [stored, isPremium] = await Promise.all([
      this.settingsRepository.findPrivacyByUserId(userId),
      this.entitlementService.hasActivePremiumSubscription(userId),
    ]);
    if (!stored) {
      throw new NotFoundException('User not found.');
    }
    return toResponse(stored, isPremium);
  }

  /**
   * Applies a partial privacy update. Only the fields present in [dto] are
   * written; omitted fields are preserved. An empty patch is a no-op that simply
   * returns the current settings (no wasted write).
   *
   * Turning a feature ON requires an active premium subscription (403
   * otherwise). Turning one OFF never does, so a member can always clear a
   * flag — including one stored before these features became premium-only.
   */
  async updatePrivacySettings(
    userId: string,
    dto: UpdatePrivacyDto,
  ): Promise<PrivacySettingsResponse> {
    const data = this.pickSuppliedFields(dto);
    if (Object.keys(data).length === 0) {
      return this.getPrivacySettings(userId);
    }

    const isPremium =
      await this.entitlementService.hasActivePremiumSubscription(userId);
    const enabling = Object.values(data).some((value) => value === true);
    if (enabling && !isPremium) {
      throw new ForbiddenException(
        'Profile and photo privacy are premium features. Upgrade to premium to turn them on.',
      );
    }

    try {
      const updated = await this.settingsRepository.updatePrivacyByUserId(
        userId,
        data,
      );
      this.logger.log(
        `Privacy settings updated for user ${userId}: ${Object.keys(data).join(', ')}.`,
      );
      return toResponse(updated, isPremium);
    } catch (error) {
      if (isRecordNotFound(error)) {
        throw new NotFoundException('User not found.');
      }
      throw error;
    }
  }

  /** Narrows the DTO to exactly the fields the caller sent, so a `PATCH` never
   *  overwrites a preference the caller didn't mention. `hideMyProfile` is
   *  stored in the `profileVisibleToPremiumOnly` column; the legacy key is
   *  honoured only when the new one is absent. */
  private pickSuppliedFields(dto: UpdatePrivacyDto): Partial<PrivacySettings> {
    const data: Partial<PrivacySettings> = {};
    const hideMyProfile = dto.hideMyProfile ?? dto.profileVisibleToPremiumOnly;
    if (hideMyProfile !== undefined) {
      data.profileVisibleToPremiumOnly = hideMyProfile;
    }
    if (dto.hidePhotosFromNonConnections !== undefined) {
      data.hidePhotosFromNonConnections = dto.hidePhotosFromNonConnections;
    }
    return data;
  }
}

/** Stored flags -> what is actually enforced for this caller. */
function toResponse(
  stored: PrivacySettings,
  isPremium: boolean,
): PrivacySettingsResponse {
  const hideMyProfile = isPremium && stored.profileVisibleToPremiumOnly;
  return {
    isPremium,
    hideMyProfile,
    hidePhotosFromNonConnections:
      isPremium && stored.hidePhotosFromNonConnections,
    profileVisibleToPremiumOnly: hideMyProfile,
  };
}
