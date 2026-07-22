import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type { Prisma } from '../../../../../../libs/database/generated/client';

// The subset of partner_preferences columns the CRUD API and the feed filter
// read/write. Kept as a Prisma type so the repository stays schema-accurate.
export type PartnerPreferenceRow = Prisma.PartnerPreferenceGetPayload<object>;

@Injectable()
export class PreferenceRepository {
  constructor(private readonly prisma: PrismaService) {}

  findByUserId(userId: string): Promise<PartnerPreferenceRow | null> {
    return this.prisma.partnerPreference.findUnique({ where: { userId } });
  }

  /**
   * Single source of truth for a user's preferences. Upsert so the first
   * PUT creates the row (a user who registered before the model existed, or
   * one editing prefs outside the wizard) and later PUTs update it.
   */
  upsert(
    userId: string,
    data: Prisma.PartnerPreferenceUncheckedCreateInput,
  ): Promise<PartnerPreferenceRow> {
    const { userId: _ignored, ...rest } = data;
    return this.prisma.partnerPreference.upsert({
      where: { userId },
      create: { userId, ...rest },
      update: rest,
    });
  }
}
