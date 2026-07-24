import { BadRequestException, Injectable } from '@nestjs/common';
import type { RegistrationStep } from '../../../../../../libs/database/generated/client';
import { ProfileRepository } from '../repositories/profile.repository';
import { ProfileCompletionService } from './profile-completion.service';
import {
  ProfileCompletionModuleEntity,
  VerificationSubStatusEntity,
} from '../entities/profile-completion.entity';

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
  completionBreakdown: ProfileCompletionModuleEntity[];
  verificationBreakdown: VerificationSubStatusEntity[];
  data: Record<string, unknown>;
}

@Injectable()
export class ProfileDraftService {
  constructor(
    private readonly profileRepository: ProfileRepository,
    private readonly completionService: ProfileCompletionService,
  ) {}

  async getDraft(userId: string): Promise<DraftResponse> {
    const step =
      await this.profileRepository.getOrCreateRegistrationStep(userId);
    return this.toDraftResponse(userId, step);
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

    // mergeDraftSection's UPDATE already RETURNs the fully merged row — a
    // trailing getDraft() call here would just re-run the expensive
    // getOrCreateRegistrationStep round trip (see its comment) to re-fetch
    // data we already have.
    const step = await this.profileRepository.mergeDraftSection(
      userId,
      section,
      sectionData as Record<string, unknown>,
      stepNumber,
    );
    return this.toDraftResponse(userId, step);
  }

  // completionPercentage comes from ProfileCompletionService — the single
  // authoritative scorer also used by ProfileService (GET /profiles/me) —
  // rather than a separately-weighted local formula, so the figure shown
  // mid-wizard never disagrees with the one shown after finalize().
  private async toDraftResponse(
    userId: string,
    step: RegistrationStep,
  ): Promise<DraftResponse> {
    const draftData = step.draftData as Record<string, unknown>;
    const completion = await this.completionService.calculate(
      userId,
      draftData,
    );
    return {
      currentStep: step.currentStep,
      totalSteps: step.totalSteps,
      completedSteps: (step.completedSteps as number[]) ?? [],
      isComplete: step.isComplete,
      completionPercentage: completion.percentage,
      completionBreakdown: completion.breakdown,
      verificationBreakdown: completion.verificationBreakdown,
      data: draftData,
    };
  }
}
