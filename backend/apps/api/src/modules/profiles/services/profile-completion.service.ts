import { Injectable } from '@nestjs/common';
import { PrismaService } from '@app/database';
import { ProfileRepository } from '../repositories/profile.repository';
import { PhotoRepository } from '../repositories/photo.repository';
import { RecommendationDismissalRepository } from '../repositories/recommendation-dismissal.repository';
import {
  ProfileCompletionEntity,
  ProfileCompletionModuleEntity,
  ProfileRecommendationEntity,
  VerificationSubStatusEntity,
} from '../entities/profile-completion.entity';
import { RECOMMENDATION_CARDS } from '../domain/recommendation-cards';
import {
  isFamilyDetailsComplete,
  isFamilySectionTouched,
  isHoroscopeDetailsValid,
  isHoroscopeSectionTouched,
} from '../validation/registration-rules';
import {
  registrationItemStatuses,
  registrationScore,
} from '../validation/required-fields';

/**
 * The four slices of the 100-point score.
 *
 * `registration` absorbs the seven modules whose content the registration flow
 * already collects — the old registration 20, education 10, physical 5,
 * lifestyle 5, psychology 3, partnerPreference 5 and photos 12 — because a
 * member who answered every registration question was scoring 20% and being
 * docked for fields nobody asked them for. Those modules each demanded MORE
 * than registration does (work location; weight and disability;
 * smoking/drinking/fitness/hobbies/about-me; a quiz; partner filters), so they
 * sat at zero for a complete new profile.
 *
 * Family, horoscope and verification keep their exact previous weights and
 * their exact previous rules: they are the sections that genuinely remain
 * after registration, and they are what the completion screen now asks for.
 *
 * The fields those absorbed modules wanted beyond registration are not scored
 * at all any more. They remain collectable and optional.
 */
const REGISTRATION_WEIGHT = 60;
const FAMILY_WEIGHT = 10;
const HOROSCOPE_WEIGHT = 5;
const VERIFICATION_WEIGHT = 25;

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
    private readonly dismissalRepository: RecommendationDismissalRepository,
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
    const [
      draftData,
      photoCount,
      user,
      kycRows,
      dismissedKeys,
      quizCount,
      partnerPreferenceRow,
    ] = await Promise.all([
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
      // Two extra reads on this hot path (every wizard "Continue" recomputes
      // completion), both single-column and index-covered on user_id. They
      // are here rather than on a second endpoint precisely so Home and Edit
      // Profile cannot drift: one response carries the percentage AND the
      // cards, so the two screens physically cannot be looking at different
      // states of the same profile.
      this.dismissalRepository.findKeysForUser(userId),
      this.prisma.userQuizResponse.count({ where: { userId } }),
      // Existence only — GET /discover/preferences never creates this row
      // (PreferencesService reads with `row?.field ?? DEFAULTS.field`), so a
      // row present here means the member has actually submitted the PUT at
      // least once, not merely viewed the schema defaults.
      this.prisma.partnerPreference.findUnique({
        where: { userId },
        select: { userId: true },
      }),
    ]);

    const data = (draftData ?? {}) as Record<string, Section>;
    const section = (name: string): Section => data[name] ?? {};

    const approvedDocTypes = new Set(kycRows.map((row) => row.docType));

    const family = section('familyDetails');
    const horoscope = section('horoscopeDetails');

    // The 'registration' slice is scored field by field rather than as one
    // all-or-nothing block. Before this it could only say "incomplete", which
    // told a member with nineteen of twenty answers exactly what it told a
    // member with none — and gave them nothing to act on. It is now scored
    // over its 21 items (the 20 counted draft fields plus at least one photo),
    // so partial answers earn partial credit and the client can name the gaps.
    const photosComplete = photoCount > 0;
    const fieldStatuses = registrationItemStatuses(data, photosComplete);
    const { completed: itemsAnswered, total: itemsCounted } = registrationScore(
      data,
      photosComplete,
    );
    const registrationComplete = itemsAnswered === itemsCounted;
    const registrationEarned = Math.round(
      (REGISTRATION_WEIGHT * itemsAnswered) / itemsCounted,
    );

    const familyComplete =
      isFamilySectionTouched(family) && isFamilyDetailsComplete(family);
    const horoscopeComplete =
      isHoroscopeSectionTouched(horoscope) &&
      isHoroscopeDetailsValid(horoscope);

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

    // Four slices, and only four. Family, horoscope and verification are
    // unchanged in weight and in rule; registration is the rest.
    const binaryModules: ProfileCompletionModuleEntity[] = [
      {
        id: 'registration',
        weight: REGISTRATION_WEIGHT,
        earned: registrationEarned,
        isComplete: registrationComplete,
        wizardStep: 0,
      },
      {
        id: 'family',
        weight: FAMILY_WEIGHT,
        earned: familyComplete ? FAMILY_WEIGHT : 0,
        isComplete: familyComplete,
        wizardStep: 7,
      },
      {
        id: 'horoscope',
        weight: HOROSCOPE_WEIGHT,
        earned: horoscopeComplete ? HOROSCOPE_WEIGHT : 0,
        isComplete: horoscopeComplete,
        wizardStep: 8,
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
        weight: VERIFICATION_WEIGHT,
        earned: verificationEarned,
        isComplete: verificationEarned >= VERIFICATION_WEIGHT,
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

    // The psychology quiz is a completion SIGNAL only. It has no module, no
    // weight, and no term in `percentage` above — finishing it (or not)
    // cannot move the figure until its scoring is explicitly approved. It
    // appears here so the optional card can show the right state.
    const psychologyComplete = quizCount > 0;

    // Same shape as psychology: a signal for the optional card, no module,
    // no weight, no term in `percentage`. A saved PartnerPreference row is
    // real evidence the member submitted the PUT — see the fetch above for
    // why a missing row can't be confused with "saw the defaults."
    const partnerPreferenceComplete = partnerPreferenceRow !== null;

    // Registration splits into two cards: the answers, and the photo. A
    // member missing only a photo is asked for a photo, not told to "complete
    // registration" — and both stand in for the whole group, which is why the
    // client shows these INSTEAD of the section cards while registration is
    // unfinished (see `registrationGroup`).
    // Excludes the photo item deliberately — it is the `photo` card's whole
    // subject, and counting it here would make the two cards say the same
    // thing to a member who has answered everything but uploaded nothing.
    const registrationFieldsComplete = fieldStatuses
      .filter((field) => field.section !== 'photos')
      .every((field) => field.isComplete || field.optional);

    const cardComplete: Record<string, boolean> = {
      registration: registrationFieldsComplete,
      photo: photosComplete,
      about_family: familyComplete,
      horoscope: horoscopeComplete,
      verification: verificationEarned >= VERIFICATION_WEIGHT,
      psychology: psychologyComplete,
      partner_preference: partnerPreferenceComplete,
    };

    const dismissed = new Set(dismissedKeys);
    const recommendations: ProfileRecommendationEntity[] =
      RECOMMENDATION_CARDS.map((card) => ({
        key: card.key,
        isComplete: cardComplete[card.key] ?? false,
        isDismissed: dismissed.has(card.key),
        affectsScore: card.affectsScore,
        wizardStep: card.wizardStep,
      }));

    const completion = new ProfileCompletionEntity();
    completion.percentage = percentage;
    completion.completedSections = completedSections;
    completion.missingSections = missingSections;
    completion.breakdown = modules;
    completion.verificationBreakdown = verificationBreakdown;
    completion.requiredFields = fieldStatuses;
    completion.registrationComplete = registrationComplete;
    completion.recommendations = recommendations;
    return completion;
  }
}
