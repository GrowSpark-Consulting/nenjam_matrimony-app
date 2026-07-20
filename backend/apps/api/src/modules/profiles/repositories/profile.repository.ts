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

  async getOrCreateRegistrationStep(userId: string): Promise<RegistrationStep> {
    return this.prisma.registrationStep.upsert({
      where: { userId },
      update: {},
      create: { userId },
    });
  }

  async mergeDraftSection(
    userId: string,
    section: string,
    sectionData: Record<string, unknown>,
    stepNumber: number,
  ): Promise<RegistrationStep> {
    console.log(`[TRACE] ProfileRepository.mergeDraftSection(${section}) before upsert`);
    console.time(`[TRACE] registrationStep.upsert(${section})`);
    const existing = await this.getOrCreateRegistrationStep(userId);
    console.timeEnd(`[TRACE] registrationStep.upsert(${section})`);
    console.log(`[TRACE] ProfileRepository.mergeDraftSection(${section}) after upsert, before update`);

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

    console.time(`[TRACE] registrationStep.update(${section})`);
    const result = await this.prisma.registrationStep.update({
      where: { userId },
      data: {
        draftData: draftData as Prisma.InputJsonValue,
        completedSteps: Array.from(completedSteps).sort((a, b) => a - b),
        currentStep: Math.max(existing.currentStep, stepNumber),
        lastSavedAt: new Date(),
      },
    });
    console.timeEnd(`[TRACE] registrationStep.update(${section})`);
    console.log(`[TRACE] ProfileRepository.mergeDraftSection(${section}) after update`);
    return result;
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

  // Upsert, not create — finalize() can be called again (e.g. the user edits
  // and resubmits the wizard), and must update the existing row rather than
  // throw on UserProfile.userId's unique constraint or create a duplicate.
  async upsertProfile(
    userId: string,
    data: Omit<Prisma.UserProfileCreateInput, 'user'>,
  ): Promise<ProfileEntity> {
    const row = await this.prisma.userProfile.upsert({
      where: { userId },
      create: { ...data, user: { connect: { id: userId } } },
      update: data,
    });
    return this.toEntity(row);
  }

  async upsertAstrologyProfile(
    userId: string,
    data: Omit<Prisma.AstrologyProfileCreateInput, 'user'>,
  ): Promise<void> {
    await this.prisma.astrologyProfile.upsert({
      where: { userId },
      create: { ...data, user: { connect: { id: userId } } },
      update: data,
    });
  }

  async upsertPartnerPreference(
    userId: string,
    data: Omit<Prisma.PartnerPreferenceCreateInput, 'user'>,
  ): Promise<void> {
    await this.prisma.partnerPreference.upsert({
      where: { userId },
      create: { ...data, user: { connect: { id: userId } } },
      update: data,
    });
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
