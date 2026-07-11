import { BadRequestException, Injectable } from '@nestjs/common';
import { ProfileRepository } from '../repositories/profile.repository';

// Order matches the Flutter wizard's 12 steps (profile_draft.dart). Steps 11
// (photos) and 12 (verification) aren't stored here — see PhotoController
// and the verification/trust-score modules respectively.
export const DRAFT_SECTIONS = [
  'basicDetails',
  'religionDetails',
  'languageDetails',
  'locationDetails',
  'educationDetails',
  'physicalDetails',
  'lifestyleDetails',
  'familyDetails',
  'horoscopeDetails',
  'partnerPreference',
] as const;

export type DraftSection = (typeof DRAFT_SECTIONS)[number];

export interface DraftResponse {
  currentStep: number;
  totalSteps: number;
  completedSteps: number[];
  isComplete: boolean;
  completionPercentage: number;
  data: Record<string, unknown>;
}

@Injectable()
export class ProfileDraftService {
  constructor(private readonly profileRepository: ProfileRepository) {}

  async getDraft(userId: string): Promise<DraftResponse> {
    const step =
      await this.profileRepository.getOrCreateRegistrationStep(userId);
    const draftData = step.draftData as Record<string, unknown>;

    return {
      currentStep: step.currentStep,
      totalSteps: step.totalSteps,
      completedSteps: (step.completedSteps as number[]) ?? [],
      isComplete: step.isComplete,
      completionPercentage: this.computeCompletionPercentage(draftData),
      data: draftData,
    };
  }

  async updateSection(
    userId: string,
    section: DraftSection,
    sectionData: object,
  ): Promise<DraftResponse> {
    const stepNumber = DRAFT_SECTIONS.indexOf(section) + 1;
    if (stepNumber === 0) {
      throw new BadRequestException(`Unknown draft section: ${section}`);
    }

    await this.profileRepository.mergeDraftSection(
      userId,
      section,
      sectionData as Record<string, unknown>,
      stepNumber,
    );
    return this.getDraft(userId);
  }

  // Mirrors ProfileDraft.completionPercentage in
  // Frontend/lib/features/registration/domain/models/profile_draft.dart —
  // same required-field weighting, kept in sync deliberately.
  private computeCompletionPercentage(
    draftData: Record<string, unknown>,
  ): number {
    let filled = 0;
    let total = 0;

    const section = (name: DraftSection): Record<string, unknown> =>
      (draftData[name] as Record<string, unknown>) ?? {};
    const has = (value: unknown): boolean =>
      typeof value === 'string' ? value.length > 0 : value != null;

    const basic = section('basicDetails');
    total += 6;
    filled += [
      'firstName',
      'lastName',
      'gender',
      'dob',
      'maritalStatus',
      'profileCreatedFor',
    ].filter((field) => has(basic[field])).length;

    const religion = section('religionDetails');
    total += 3;
    filled += ['religion', 'caste', 'community'].filter((field) =>
      has(religion[field]),
    ).length;

    const language = section('languageDetails');
    total += 1;
    if (has(language.motherTongue)) filled++;

    const location = section('locationDetails');
    total += 3;
    filled += ['country', 'state', 'city'].filter((field) =>
      has(location[field]),
    ).length;

    const education = section('educationDetails');
    total += 2;
    filled += ['qualification', 'occupation'].filter((field) =>
      has(education[field]),
    ).length;

    const physical = section('physicalDetails');
    total += 1;
    if (has(physical.height)) filled++;

    const family = section('familyDetails');
    total += 2;
    filled += ['familyType', 'familyValues'].filter((field) =>
      has(family[field]),
    ).length;

    if (total === 0) return 0;
    return Math.min(100, Math.round((filled / total) * 100));
  }
}
