import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  AstrologyProfile,
  PartnerPreference,
  Prisma,
  RegistrationStep,
  UserProfile,
} from '../../../../../../libs/database/generated/client';
import { ProfileEntity } from '../entities/profile.entity';
import { PartnerPreferenceEntity } from '../entities/partner-preference.entity';
import { AstrologyProfileEntity } from '../entities/astrology-profile.entity';

@Injectable()
export class ProfileRepository {
  constructor(private readonly prisma: PrismaService) {}

  // Deliberately raw SQL, not `prisma.registrationStep.upsert()`: because the
  // conflict target (`userId`) isn't this model's `@id`, Prisma's query
  // engine doesn't compile that upsert into a single `INSERT ... ON
  // CONFLICT` — it falls back to an explicit read-then-write transaction (3
  // SELECTs + COMMIT). Measured on this dataset: ~1.0-1.3s per call against
  // Neon vs. ~250-300ms for the single-statement version below. This method
  // is called multiple times per wizard "Continue" tap (see
  // ProfileDraftService/ProfileService), so that difference was the
  // dominant cause of the reported 5+s save delay. Column list mirrors the
  // Prisma-generated one exactly — update both if the schema changes.
  async getOrCreateRegistrationStep(userId: string): Promise<RegistrationStep> {
    const rows = await this.prisma.$queryRaw<RegistrationStep[]>`
      INSERT INTO registration_steps (id, user_id, updated_at)
      VALUES (gen_random_uuid(), ${userId}, now())
      ON CONFLICT (user_id) DO UPDATE SET updated_at = now()
      RETURNING
        id,
        user_id AS "userId",
        current_step AS "currentStep",
        total_steps AS "totalSteps",
        completed_steps AS "completedSteps",
        draft_data AS "draftData",
        last_saved_at AS "lastSavedAt",
        is_complete AS "isComplete",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
    `;
    return rows[0];
  }

  async mergeDraftSection(
    userId: string,
    section: string,
    sectionData: Record<string, unknown>,
    stepNumber: number,
  ): Promise<RegistrationStep> {
    const existing = await this.getOrCreateRegistrationStep(userId);

    const draftData = {
      ...(existing.draftData as Record<string, unknown>),
      [section]: {
        ...((existing.draftData as Record<string, unknown>)[section] as
          Record<string, unknown> | undefined),
        ...sectionData,
      },
    };
    const completedSteps = new Set((existing.completedSteps as number[]) ?? []);
    completedSteps.add(stepNumber);

    return this.prisma.registrationStep.update({
      where: { userId },
      data: {
        draftData: draftData as Prisma.InputJsonValue,
        completedSteps: Array.from(completedSteps).sort((a, b) => a - b),
        currentStep: Math.max(existing.currentStep, stepNumber),
        lastSavedAt: new Date(),
      },
    });
  }

  async markComplete(userId: string): Promise<RegistrationStep> {
    return this.prisma.registrationStep.update({
      where: { userId },
      data: { isComplete: true },
    });
  }

  async findProfileByUserId(userId: string): Promise<ProfileEntity | null> {
    const row = await this.prisma.userProfile.findUnique({
      where: { userId },
    });
    return row ? this.toEntity(row) : null;
  }

  // Deliberately update-then-create, not `.upsert()`: same issue as
  // getOrCreateRegistrationStep above — because `userId` isn't this model's
  // `@id`, `.upsert()` compiles into a 3-SELECT+COMMIT transaction instead of
  // one statement. `.update()`/`.create()` alone don't have that problem —
  // each compiles to a single round trip. This runs on every wizard
  // "Continue" tap once the mandatory sections are complete (see
  // ProfileService.syncMatchableFromDraft), so it was the dominant
  // contributor to a still-5+s save even after the RegistrationStep fix —
  // measured: ~5-6s here vs. ~1s for the equivalent update-then-create.
  // update() throws P2025 ("record to update not found") on a genuinely new
  // user's first materialize — the only case that falls through to create().
  private async updateThenCreate<T>(
    update: () => Promise<T>,
    create: () => Promise<T>,
  ): Promise<T> {
    try {
      return await update();
    } catch (error) {
      if ((error as { code?: string }).code === 'P2025') {
        return create();
      }
      throw error;
    }
  }

  async upsertProfile(
    userId: string,
    data: Omit<Prisma.UserProfileCreateInput, 'user'>,
  ): Promise<ProfileEntity> {
    const row = await this.updateThenCreate(
      () => this.prisma.userProfile.update({ where: { userId }, data }),
      () =>
        this.prisma.userProfile.create({
          data: { ...data, user: { connect: { id: userId } } },
        }),
    );
    return this.toEntity(row);
  }

  async upsertAstrologyProfile(
    userId: string,
    data: Omit<Prisma.AstrologyProfileCreateInput, 'user'>,
  ): Promise<void> {
    await this.updateThenCreate(
      () => this.prisma.astrologyProfile.update({ where: { userId }, data }),
      () =>
        this.prisma.astrologyProfile.create({
          data: { ...data, user: { connect: { id: userId } } },
        }),
    );
  }

  async upsertPartnerPreference(
    userId: string,
    data: Omit<Prisma.PartnerPreferenceCreateInput, 'user'>,
  ): Promise<void> {
    await this.updateThenCreate(
      () => this.prisma.partnerPreference.update({ where: { userId }, data }),
      () =>
        this.prisma.partnerPreference.create({
          data: { ...data, user: { connect: { id: userId } } },
        }),
    );
  }

  async findPartnerPreference(
    userId: string,
  ): Promise<PartnerPreferenceEntity | null> {
    const row = await this.prisma.partnerPreference.findUnique({
      where: { userId },
    });
    return row ? this.toPartnerPreferenceEntity(row) : null;
  }

  async findAstrologyProfile(
    userId: string,
  ): Promise<AstrologyProfileEntity | null> {
    const row = await this.prisma.astrologyProfile.findUnique({
      where: { userId },
    });
    return row ? this.toAstrologyProfileEntity(row) : null;
  }

  // Live recompute, not just a getter — callers use this to persist a fresh
  // profileCompletePct after any write that could change it (finalize, photo
  // add/delete, preference/astrology upsert).
  async updateProfileCompletePct(userId: string, pct: number): Promise<void> {
    await this.prisma.userProfile.update({
      where: { userId },
      data: { profileCompletePct: pct },
    });
  }

  /**
   * Stores the caller's own device coordinates for Near Me.
   *
   * `update`, not `upsert`: a UserProfile row only exists once registration is
   * finalized, and a member who has not finished registering has no business
   * being discoverable. Prisma raises P2025 when the row is missing, which the
   * service turns into a 404 rather than quietly creating a profile that
   * consists of nothing but a pair of coordinates.
   */
  async updateLocation(
    userId: string,
    latitude: number,
    longitude: number,
    accuracyM: number | null,
  ): Promise<{
    latitude: number | null;
    longitude: number | null;
    locationAccuracyM: number | null;
    locationUpdatedAt: Date | null;
  }> {
    return this.prisma.userProfile.update({
      where: { userId },
      data: {
        latitude,
        longitude,
        locationAccuracyM: accuracyM,
        // Server clock, never a client-supplied timestamp: this drives
        // staleness decisions, and a device with a wrong clock (or a caller
        // choosing its own value) would otherwise make a fix look fresher than
        // it is.
        locationUpdatedAt: new Date(),
      },
      select: {
        latitude: true,
        longitude: true,
        locationAccuracyM: true,
        locationUpdatedAt: true,
      },
    });
  }

  private toEntity(row: UserProfile): ProfileEntity {
    const entity = new ProfileEntity();
    Object.assign(entity, {
      ...row,
      annualIncomeLakhs: row.annualIncomeLakhs?.toString() ?? null,
    });
    return entity;
  }

  private toPartnerPreferenceEntity(
    row: PartnerPreference,
  ): PartnerPreferenceEntity {
    const entity = new PartnerPreferenceEntity();
    Object.assign(entity, {
      ...row,
      preferredReligions: row.preferredReligions as string[],
      preferredCastes: row.preferredCastes as string[],
      minIncomeLakhs: row.minIncomeLakhs?.toString() ?? null,
      preferredCities: row.preferredCities as string[],
      preferredStates: row.preferredStates as string[],
      preferredEducation: row.preferredEducation as string[],
      preferredOccupations: row.preferredOccupations as string[],
      preferredMotherTongues: row.preferredMotherTongues as string[],
      maritalStatusPref: row.maritalStatusPref as string[],
    });
    return entity;
  }

  private toAstrologyProfileEntity(
    row: AstrologyProfile,
  ): AstrologyProfileEntity {
    const entity = new AstrologyProfileEntity();
    Object.assign(entity, row);
    return entity;
  }
}
