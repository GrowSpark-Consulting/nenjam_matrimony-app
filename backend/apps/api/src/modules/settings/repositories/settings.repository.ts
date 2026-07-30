import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';

/** The per-user privacy preferences, as a plain shape (never a Prisma model) so
 *  nothing above this layer depends on the ORM. */
export interface PrivacySettings {
  profileVisibleToPremiumOnly: boolean;
  hidePhotosFromNonConnections: boolean;
}

// Single source of truth for the columns this repository reads/returns, so the
// select and the return type can never drift apart.
const PRIVACY_SELECT = {
  profileVisibleToPremiumOnly: true,
  hidePhotosFromNonConnections: true,
} as const;

/**
 * Persistence for user settings. Privacy preferences live directly on the `User`
 * row (two boolean columns), so there is no separate table to join — reads and
 * writes are a single indexed lookup by primary key. This layer performs DB
 * access only; defaulting, partial-update rules, and ownership live in the
 * service.
 */
@Injectable()
export class SettingsRepository {
  constructor(private readonly prisma: PrismaService) {}

  /** The caller's privacy settings, or null when the user row doesn't exist. */
  findPrivacyByUserId(userId: string): Promise<PrivacySettings | null> {
    return this.prisma.user.findUnique({
      where: { id: userId },
      select: PRIVACY_SELECT,
    });
  }

  /** Writes the given columns and returns the full, current privacy settings.
   *  Only the keys present in `data` are written (Prisma treats `undefined` as
   *  "leave unchanged"); the service guarantees `data` holds only supplied
   *  fields. Throws Prisma `P2025` when the user row doesn't exist. */
  updatePrivacyByUserId(
    userId: string,
    data: Partial<PrivacySettings>,
  ): Promise<PrivacySettings> {
    return this.prisma.user.update({
      where: { id: userId },
      data,
      select: PRIVACY_SELECT,
    });
  }
}
