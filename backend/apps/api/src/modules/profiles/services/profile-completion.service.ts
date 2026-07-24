import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import { ProfileRepository } from '../repositories/profile.repository';
import { PhotoRepository } from '../repositories/photo.repository';
import {
  ProfileCompletionEntity,
  ProfileCompletionModuleEntity,
  VerificationSubStatusEntity,
} from '../entities/profile-completion.entity';
import {
  isBasicDetailsComplete,
  isEducationDetailsValid,
  isEducationSectionTouched,
  isFamilyDetailsComplete,
  isFamilySectionTouched,
  isHoroscopeDetailsValid,
  isHoroscopeSectionTouched,
  isLanguageDetailsComplete,
  isLifestyleDetailsValid,
  isLifestyleSectionTouched,
  isLocationDetailsComplete,
  isPartnerPreferenceComplete,
  isPhysicalDetailsValid,
  isPhysicalSectionTouched,
  isReligionDetailsComplete,
} from '../validation/registration-rules';

type Section = Record<string, unknown>;

/**
 * The single authoritative profile-completion calculator — the only place
 * in the codebase that assigns the 0-100 score. ProfileService (finalized
 * profile, GET /profiles/me) and ProfileDraftService (in-progress wizard
 * draft, GET /profiles/draft) both call this rather than computing their
 * own number, so the figure a user sees is always the same regardless of
 * which endpoint produced it.
 *
 * Reads straight from RegistrationStep.draftData for Steps 1-9 (rather than
 * the derived UserProfile columns) because writeProfileFromDraft() copies
 * whatever's in the draft as-is, including a touched-but-invalid optional
 * section — the draft plus registration-rules.ts's touched/valid pair is
 * the only place "did the user actually finish this, or just start it" can
 * still be answered correctly.
 *
 * Weights (must sum to 100 — enforced by the unit tests):
 *   Mandatory (Steps 1-4, all-or-nothing) ........... 20
 *   Education & Career ................................ 10
 *   Physical Details ................................... 5
 *   Lifestyle & Hobbies ................................ 5
 *   Family Details ..................................... 10
 *   Horoscope / Astro ................................... 5
 *   Psychology / Personality ............................ 3
 *   Partner Preference ................................... 5
 *   Photos .............................................. 12
 *   Verification (5 independent flags, 5 each) ......... 25
 */
@Injectable()
export class ProfileCompletionService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly profileRepository: ProfileRepository,
    private readonly photoRepository: PhotoRepository,
  ) {}

  // [prefetchedDraftData] lets a caller that just fetched/merged the
  // RegistrationStep row itself (ProfileDraftService, or ProfileService's
  // finalize()/syncMatchableFromDraft(), which both already hold the draft
  // in scope) pass its `draftData` straight through instead of this method
  // re-fetching the row — see ProfileRepository.getOrCreateRegistrationStep's
  // own comment on why that round trip is expensive and worth avoiding on
  // the wizard's hot "Continue" save path.
  async calculate(
    userId: string,
    prefetchedDraftData?: Record<string, unknown>,
  ): Promise<ProfileCompletionEntity> {
    const [draftData, photoCount, user, kycRows, quizResponseCount] =
      await Promise.all([
        prefetchedDraftData
          ? Promise.resolve(prefetchedDraftData)
          : this.profileRepository
              .getOrCreateRegistrationStep(userId)
              .then((step) => step.draftData as Record<string, unknown>),
        this.photoRepository.countForUser(userId),
        this.prisma.user.findUnique({
          where: { id: userId },
          select: { phone: true },
        }),
        this.prisma.kycVerification.findMany({
          where: { userId, status: 'APPROVED' },
          select: { docType: true },
        }),
        this.prisma.userQuizResponse.count({ where: { userId } }),
      ]);

    const data = (draftData ?? {}) as Record<string, Section>;
    const section = (name: string): Section => data[name] ?? {};

    const approvedDocTypes = new Set(kycRows.map((row) => row.docType));

    const basic = section('basicDetails');
    const religion = section('religionDetails');
    const language = section('languageDetails');
    const location = section('locationDetails');
    const education = section('educationDetails');
    const physical = section('physicalDetails');
    const lifestyle = section('lifestyleDetails');
    const family = section('familyDetails');
    const horoscope = section('horoscopeDetails');
    const partnerPref = section('partnerPreference');

    const mandatoryComplete =
      isBasicDetailsComplete(basic) &&
      isReligionDetailsComplete(religion) &&
      isLanguageDetailsComplete(language) &&
      isLocationDetailsComplete(location);

    const educationComplete =
      isEducationSectionTouched(education) &&
      isEducationDetailsValid(education);
    const physicalComplete =
      isPhysicalSectionTouched(physical) && isPhysicalDetailsValid(physical);
    const lifestyleComplete =
      isLifestyleSectionTouched(lifestyle) &&
      isLifestyleDetailsValid(lifestyle);
    const familyComplete =
      isFamilySectionTouched(family) && isFamilyDetailsComplete(family);
    const horoscopeComplete =
      isHoroscopeSectionTouched(horoscope) &&
      isHoroscopeDetailsValid(horoscope);
    const psychologyComplete = quizResponseCount > 0;
    const partnerPreferenceComplete = isPartnerPreferenceComplete(partnerPref);
    const photosComplete = photoCount > 0;

    // Each flag here is real, backend-verified evidence — never a
    // client-submitted or "pending" state:
    //  - mobile: User.phone is set ONLY from the Firebase ID token's
    //    verified `phone_number` claim (see FirebaseAuthGuard.resolveUser),
    //    which Firebase itself only includes for a phone-auth account that
    //    completed OTP verification. There is no write path that lets a
    //    client set this to an unverified number.
    //  - income/asset/aadhaar/nri: an APPROVED KycVerification row for that
    //    doc type (query below already filters to status: APPROVED, so
    //    PENDING/REJECTED rows are invisible here regardless of what else
    //    exists for the user).
    const mobileVerified = Boolean(user?.phone);
    const incomeVerified = approvedDocTypes.has('INCOME_PROOF');
    const assetVerified = approvedDocTypes.has('ASSET_PROOF');
    const aadhaarVerified = approvedDocTypes.has('AADHAAR');
    const nriVerified = approvedDocTypes.has('NRI_PROOF');
    const verificationEarned =
      (mobileVerified ? 5 : 0) +
      (incomeVerified ? 5 : 0) +
      (assetVerified ? 5 : 0) +
      (aadhaarVerified ? 5 : 0) +
      (nriVerified ? 5 : 0);

    const binaryModules: ProfileCompletionModuleEntity[] = [
      {
        id: 'registration',
        weight: 20,
        earned: mandatoryComplete ? 20 : 0,
        isComplete: mandatoryComplete,
        wizardStep: 0,
      },
      {
        id: 'education',
        weight: 10,
        earned: educationComplete ? 10 : 0,
        isComplete: educationComplete,
        wizardStep: 4,
      },
      {
        id: 'physical',
        weight: 5,
        earned: physicalComplete ? 5 : 0,
        isComplete: physicalComplete,
        wizardStep: 5,
      },
      {
        id: 'lifestyle',
        weight: 5,
        earned: lifestyleComplete ? 5 : 0,
        isComplete: lifestyleComplete,
        wizardStep: 6,
      },
      {
        id: 'family',
        weight: 10,
        earned: familyComplete ? 10 : 0,
        isComplete: familyComplete,
        wizardStep: 7,
      },
      {
        id: 'horoscope',
        weight: 5,
        earned: horoscopeComplete ? 5 : 0,
        isComplete: horoscopeComplete,
        wizardStep: 8,
      },
      {
        id: 'psychology',
        weight: 3,
        earned: psychologyComplete ? 3 : 0,
        isComplete: psychologyComplete,
        wizardStep: 9,
      },
      {
        id: 'partnerPreference',
        weight: 5,
        earned: partnerPreferenceComplete ? 5 : 0,
        isComplete: partnerPreferenceComplete,
        wizardStep: 10,
      },
      {
        id: 'photos',
        weight: 12,
        earned: photosComplete ? 12 : 0,
        isComplete: photosComplete,
        wizardStep: 11,
      },
    ];

    const nonVerificationEarned = binaryModules.reduce(
      (sum, m) => sum + m.earned,
      0,
    );
    const percentage = Math.max(
      0,
      Math.min(100, nonVerificationEarned + verificationEarned),
    );

    const modules: ProfileCompletionModuleEntity[] = [
      ...binaryModules,
      {
        id: 'verification',
        weight: 25,
        earned: verificationEarned,
        isComplete: verificationEarned >= 25,
        wizardStep: 12,
      },
    ];

    const verificationBreakdown: VerificationSubStatusEntity[] = [
      { id: 'mobile', weight: 5, isVerified: mobileVerified },
      { id: 'income', weight: 5, isVerified: incomeVerified },
      { id: 'asset', weight: 5, isVerified: assetVerified },
      { id: 'aadhaar', weight: 5, isVerified: aadhaarVerified },
      { id: 'nri', weight: 5, isVerified: nriVerified },
    ];

    const completedSections = modules
      .filter((m) => m.isComplete)
      .map((m) => m.id);
    const missingSections = modules
      .filter((m) => !m.isComplete)
      .map((m) => m.id);

    const completion = new ProfileCompletionEntity();
    completion.percentage = percentage;
    completion.completedSections = completedSections;
    completion.missingSections = missingSections;
    completion.breakdown = modules;
    completion.verificationBreakdown = verificationBreakdown;
    return completion;
  }
}
