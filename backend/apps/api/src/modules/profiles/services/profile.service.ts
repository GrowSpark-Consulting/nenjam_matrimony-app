import {
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import { ProfileRepository } from '../repositories/profile.repository';
import { PhotoRepository } from '../repositories/photo.repository';
import { ProfileDraftService } from './profile-draft.service';
import { ProfileCompletionService } from './profile-completion.service';
import { FeedInvalidationService } from '../../matches/cache/feed-invalidation.service';
import { EmailDispatchService } from '../../notifications/services/email-dispatch.service';
import { ProfileEntity } from '../entities/profile.entity';
import { PhotoEntity } from '../entities/photo.entity';
import type { LocationResponseDto } from '../dto/update-location.dto';
import {
  isBasicDetailsComplete,
  isEducationDetailsValid,
  isHoroscopeDetailsValid,
  isLanguageDetailsComplete,
  isLifestyleDetailsValid,
  isLocationDetailsComplete,
  isPhysicalDetailsValid,
  isMatchableFromDraft,
  isReligionDetailsComplete,
} from '../validation/registration-rules';

// Best-effort parsers for the free-text range/string fields the Flutter
// wizard collects. These assume the wizard's dropdown/picker values look
// like "25-30", "150-180 cm", "5 lakhs+", etc. — adjust the regexes here if
// the actual picker value format differs once the UI is wired to this API.
function parseIntRange(
  value: string | undefined,
  fallback: [number, number],
): [number, number] {
  if (!value) return fallback;
  const match = value.match(/(\d+)\D+(\d+)/);
  if (!match) return fallback;
  return [Number(match[1]), Number(match[2])];
}

function parseLeadingNumber(value: string | undefined): number | null {
  if (!value) return null;
  const match = value.match(/(\d+(\.\d+)?)/);
  return match ? Number(match[1]) : null;
}

// The wizard's height picker emits feet'inches" strings ("5'9\"", "6'0\"" —
// see step_physical.dart's _heights). parseLeadingNumber would read only the
// leading number (the FEET), storing e.g. 5 into height_cm instead of 175 —
// which then wrongly excludes the profile from any height-range partner
// filter. Convert feet+inches to centimetres; fall back to a plain-cm value
// (e.g. "175" / "175 cm") if that's ever what's stored.
function parseHeightToCm(value: string | undefined): number | null {
  if (!value) return null;
  const feetInches = value.match(/(\d+)\s*'\s*(\d+)/);
  if (feetInches) {
    const feet = Number(feetInches[1]);
    const inches = Number(feetInches[2]);
    return Math.round((feet * 12 + inches) * 2.54);
  }
  return parseLeadingNumber(value);
}

// The wizard's partner-preference height picker emits bucketed feet'inches
// ranges ("4'6\"-5'0\"", "6'0\"+", "Any" — see partner_preference_labels.dart's
// partnerPrefHeightRanges). parseIntRange's generic `(\d+)\D+(\d+)` regex reads
// the first two digit runs verbatim — for "4'6\"-5'0\"" that's the 4 and the 6
// (feet and inches of the LOWER bound alone), producing an impossible
// min=4cm/max=6cm that excludes every real profile from the feed. Parse each
// side of the range through parseHeightToCm instead so bounds land in
// realistic centimetres.
function parseHeightRangeToCm(
  value: string | undefined,
  fallback: [number, number],
): [number, number] {
  if (!value) return fallback;
  const trimmed = value.trim();
  if (/^any$/i.test(trimmed)) return fallback;

  // Open-ended lower bound, e.g. "6'0\"+".
  const plusMatch = trimmed.match(/^(.+?)\+$/);
  if (plusMatch) {
    const min = parseHeightToCm(plusMatch[1]);
    return min !== null ? [min, fallback[1]] : fallback;
  }

  // Closed range, e.g. "4'6\"-5'0\"".
  const dashIndex = trimmed.indexOf('-');
  if (dashIndex > 0) {
    const min = parseHeightToCm(trimmed.slice(0, dashIndex));
    const max = parseHeightToCm(trimmed.slice(dashIndex + 1));
    if (min !== null && max !== null) return [min, max];
  }

  return fallback;
}

function toStringArray(value: string | undefined): string[] {
  if (!value) return [];
  return value
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean);
}

// The wizard sends some fields as genuine JSON arrays already
// (languagesKnown, hobbies — see profile_draft.dart's toJson()), unlike the
// comma-separated free-text partner-preference fields toStringArray()
// handles. Accepts either shape defensively.
function toArray(value: unknown): string[] {
  if (Array.isArray(value)) return value.map((v) => String(v));
  if (typeof value === 'string') return toStringArray(value);
  return [];
}

function joinNonEmpty(...parts: (string | undefined)[]): string | undefined {
  const joined = parts
    .filter((part) => part && part.trim().length > 0)
    .join(' · ');
  return joined.length > 0 ? joined : undefined;
}

// Maps the free-text horoscope/manglik fields to AstrologyProfile's
// DoshamType enum. "Chevvai dosham" (Mars affliction) is what most
// matrimony forms mean by "manglik" — see AstrologyProfile.dosham.
function mapDosham(
  manglik?: string,
  dosham?: string,
): 'NONE' | 'CHEVVAI' | 'RAHU_KETHU' | 'SARPA' {
  const normalized = (dosham ?? '').trim().toUpperCase();
  if (['CHEVVAI', 'RAHU_KETHU', 'SARPA'].includes(normalized)) {
    return normalized as 'CHEVVAI' | 'RAHU_KETHU' | 'SARPA';
  }
  if (manglik && /^(yes|true|manglik)$/i.test(manglik.trim())) {
    return 'CHEVVAI';
  }
  return 'NONE';
}

@Injectable()
export class ProfileService {
  private readonly logger = new Logger(ProfileService.name);

  constructor(
    private readonly profileRepository: ProfileRepository,
    private readonly photoRepository: PhotoRepository,
    private readonly draftService: ProfileDraftService,
    private readonly completionService: ProfileCompletionService,
    private readonly emailDispatch: EmailDispatchService,
    private readonly feedInvalidation: FeedInvalidationService,
  ) {}

  // Assembles the full response: the finalized UserProfile plus everything
  // else the profile screen needs in one round trip — photos,
  // partner-preference, astrology (each null/[] if the user never filled
  // that optional section), and a freshly-computed completion breakdown.
  async getOwn(
    userId: string,
    prefetchedProfile?: ProfileEntity,
    prefetchedPhotos?: PhotoEntity[],
    prefetchedDraftData?: Record<string, unknown>,
  ): Promise<ProfileEntity> {
    // All 5 reads are independent (keyed only by userId, no cross-dependency
    // between them) — the only thing that used to make findProfileByUserId
    // run first was the null-check below, which doesn't need the other
    // results, so it can happen after they've all resolved together.
    // Callers that just wrote/read the profile row, photos array, or draft
    // themselves (finalize(), syncMatchableFromDraft()) can pass them in
    // here to skip the redundant re-SELECT — see writeProfileFromDraft's
    // return value and finalize()'s photo fetch below.
    const [profile, photos, partnerPreference, astrology, completion] =
      await Promise.all([
        prefetchedProfile
          ? Promise.resolve(prefetchedProfile)
          : this.profileRepository.findProfileByUserId(userId),
        prefetchedPhotos
          ? Promise.resolve(prefetchedPhotos)
          : this.photoRepository.findAllForUser(userId),
        this.profileRepository.findPartnerPreference(userId),
        this.profileRepository.findAstrologyProfile(userId),
        // See ProfileCompletionService — the single authoritative scorer,
        // shared with ProfileDraftService.getDraft()'s completionPercentage.
        this.completionService.calculate(userId, prefetchedDraftData),
      ]);
    if (!profile) {
      throw new NotFoundException('Profile has not been finalized yet.');
    }

    profile.photos = photos;
    profile.partnerPreference = partnerPreference;
    profile.astrology = astrology;
    profile.completion = completion;
    return profile;
  }

  /**
   * Stores the caller's device coordinates so they become discoverable in
   * other members' Near Me results.
   *
   * Writes only the authenticated caller's row — [userId] comes from the
   * verified Firebase token, never from the request body, so there is no way
   * to plant a location on someone else's profile.
   *
   * A missing UserProfile row (registration not finalized) surfaces from
   * Prisma as P2025; it becomes a 404 rather than a 500, because "you have no
   * profile yet" is a client-actionable state, not a server fault.
   */
  async updateLocation(
    userId: string,
    latitude: number,
    longitude: number,
    accuracyM?: number,
  ): Promise<LocationResponseDto> {
    try {
      const row = await this.profileRepository.updateLocation(
        userId,
        latitude,
        longitude,
        accuracyM ?? null,
      );

      return {
        latitude: row.latitude ?? latitude,
        longitude: row.longitude ?? longitude,
        accuracyM: row.locationAccuracyM,
        updatedAt: (row.locationUpdatedAt ?? new Date()).toISOString(),
      };
    } catch (error) {
      if ((error as { code?: string }).code === 'P2025') {
        throw new NotFoundException(
          'No profile found. Complete registration before sharing your location.',
        );
      }
      this.logger.error(
        `Failed to store location for user ${userId}: ${(error as Error).message}`,
      );
      throw error;
    }
  }

  // Reads the accumulated wizard draft (see ProfileDraftService) and writes
  // it into UserProfile / AstrologyProfile / PartnerPreference.
  async finalize(userId: string): Promise<ProfileEntity> {
    // getDraft and the photos fetch are independent reads (both keyed only by
    // userId, neither depends on the other's result) — issuing them together
    // saves one full Neon round trip versus the previous fetch-draft →
    // validate → fetch-photos sequence. The validation order below is
    // unchanged, so a missing-mandatory-field error still takes precedence
    // over the "no photos" error exactly as before.
    const [draft, photos] = await Promise.all([
      this.draftService.getDraft(userId),
      this.photoRepository.findAllForUser(userId),
    ]);
    const data = draft.data as Record<string, Record<string, unknown>>;

    const missing = this.missingRequiredFields(data);
    if (missing.length > 0) {
      throw new BadRequestException(
        `Cannot finalize profile — missing required fields: ${missing.join(', ')}`,
      );
    }

    // These checks are finalize-only — deliberately NOT part of
    // missingRequiredFields()/syncMatchableFromDraft(), so a user can still
    // become matchable before touching the skippable Education/Lifestyle/
    // Horoscope steps. They only gate the final "complete registration"
    // action, and only to reject a *half-filled* optional section — never
    // an untouched one.
    //
    // Photos and mobile verification are intentionally NOT enforced here.
    // Only Steps 1-4 are mandatory for this release: a user with zero
    // photos and no verification must still be able to finalize and reach
    // Discover at exactly 20%. Do not reintroduce a photo-count or
    // verification check in this method — see ProfileCompletionService for
    // how photos (12%) and verification (25%, 5% per independent flag)
    // are scored instead, without gating finalize.
    const incomplete: string[] = [];
    if (!isPhysicalDetailsValid(data.physicalDetails ?? {})) {
      incomplete.push(
        'physicalDetails (once started, height/weight/disability are all required — finish it or clear it)',
      );
    }
    if (!isEducationDetailsValid(data.educationDetails ?? {})) {
      incomplete.push(
        'educationDetails (once started, every field is required — finish it or clear it)',
      );
    }
    if (!isLifestyleDetailsValid(data.lifestyleDetails ?? {})) {
      incomplete.push(
        'lifestyleDetails (once started, every field is required — finish it or clear it)',
      );
    }
    if (!isHoroscopeDetailsValid(data.horoscopeDetails ?? {})) {
      incomplete.push(
        'horoscopeDetails.rashi (required once any horoscope field is filled)',
      );
    }
    // `photos` was already fetched above (Promise.all with the draft read) —
    // full rows, not just COUNT — and is reused below in
    // recalculateAndPersistCompletion's getOwn() call, so profile_photos is
    // queried only once per finalize(). Not used to gate finalize — an
    // empty array is a perfectly valid result here.
    console.log(
      `[STORY-PERF-SRV] ${Date.now()} finalize: findAllForUser complete`,
    );
    if (incomplete.length > 0) {
      throw new BadRequestException(
        `Cannot finalize profile — ${incomplete.join('; ')}`,
      );
    }

    const writtenProfile = await this.writeProfileFromDraft(userId, data);
    await this.profileRepository.markComplete(userId);
    console.log(
      `[STORY-PERF-SRV] ${Date.now()} finalize: markComplete complete`,
    );
    const result = await this.recalculateAndPersistCompletion(
      userId,
      writtenProfile,
      photos,
      data,
    );
    console.log(
      `[STORY-PERF-SRV] ${Date.now()} finalize: recalculateAndPersistCompletion complete`,
    );

    // Welcome email — queued only after every write above has committed, and
    // deliberately not awaited: finalize() is the last step of the
    // registration wizard, and the user should land on their profile without
    // waiting on Redis. EmailDispatchService swallows its own failures, so
    // this can never reject unhandled.
    void this.emailDispatch.sendWelcome(userId).catch(() => undefined);

    return result;
  }

  /**
   * Makes the user eligible for Discover/matchmaking the moment every MANDATORY
   * profile field exists — without waiting for the optional steps (photos,
   * quiz, verification) or the final Review/finalize tap. Called after every
   * wizard draft-section save (see ProfileDraftController). No-op until the
   * mandatory set is complete. Never throws: the draft is already persisted, so
   * a failure here must not fail the user's step save — they'll still become
   * matchable on the next save or at finalize().
   *
   * [draftData] lets a caller that just fetched/merged the draft (e.g.
   * ProfileDraftController.save, right after updateSection) pass it straight
   * through instead of this method re-fetching it — that re-fetch used to be
   * the single biggest contributor to the "Continue" button's save latency
   * (see ProfileRepository.getOrCreateRegistrationStep). Falls back to a
   * fresh fetch for callers that don't already have it.
   */
  async syncMatchableFromDraft(
    userId: string,
    draftData?: Record<string, Record<string, unknown>>,
  ): Promise<void> {
    try {
      const data =
        draftData ??
        ((await this.draftService.getDraft(userId)).data as Record<
          string,
          Record<string, unknown>
        >);
      // Matchability, not finalize-completeness. These are different
      // questions and this used to ask the wrong one: the finalize rules
      // demand subCaste/area/pinCode/nativePlace, all of which are NULLABLE
      // columns, and the onboarding flow collects none of them — so every
      // onboarding save returned here and `user_profiles` kept whatever a
      // previous wizard run had left. finalize() still enforces the strict
      // contract; see isMatchableFromDraft for why the sets differ.
      if (!isMatchableFromDraft(data)) return;

      const writtenProfile = await this.writeProfileFromDraft(userId, data);
      console.log(
        `[STORY-PERF-SRV] ${Date.now()} syncMatchableFromDraft: writeProfileFromDraft complete`,
      );
      await this.recalculateAndPersistCompletion(
        userId,
        writtenProfile,
        undefined,
        data,
      );
      console.log(
        `[STORY-PERF-SRV] ${Date.now()} syncMatchableFromDraft: recalculateAndPersistCompletion complete`,
      );
    } catch (error) {
      this.logger.warn(
        `Auto-materialise from draft skipped for ${userId}: ${(error as Error).message}`,
      );
    }
  }

  /**
   * Materialises the wizard draft into the real UserProfile / AstrologyProfile /
   * PartnerPreference rows (idempotent upsert) and flags the profile matchable
   * (`isProfileComplete = true`). Does NOT mark the wizard registration complete
   * (that stays in finalize()'s markComplete). Callers must have verified the
   * mandatory fields are present first (missingRequiredFields === []).
   */
  private async writeProfileFromDraft(
    userId: string,
    data: Record<string, Record<string, unknown>>,
  ): Promise<ProfileEntity> {
    const basic = data.basicDetails ?? {};
    const religion = data.religionDetails ?? {};
    const language = data.languageDetails ?? {};
    const location = data.locationDetails ?? {};
    const education = data.educationDetails ?? {};
    const physical = data.physicalDetails ?? {};
    const lifestyle = data.lifestyleDetails ?? {};
    const family = data.familyDetails ?? {};
    const horoscope = data.horoscopeDetails ?? {};
    const partnerPref = data.partnerPreference ?? {};

    const heightCm = parseHeightToCm(physical.height as string | undefined);
    const weightKg = parseLeadingNumber(physical.weight as string | undefined);
    const annualIncomeLakhs = parseLeadingNumber(
      education.annualIncome as string | undefined,
    );
    const father = (family.father ?? {}) as Record<string, unknown>;
    const mother = (family.mother ?? {}) as Record<string, unknown>;
    const siblingDetails = Array.isArray(family.siblings)
      ? (family.siblings as Record<string, unknown>[])
      : [];

    const profileWrite = this.profileRepository.upsertProfile(userId, {
      firstName: basic.firstName as string,
      lastName: basic.lastName as string,
      dob: new Date(basic.dob as string),
      gender: basic.gender as 'MALE' | 'FEMALE',
      maritalStatus:
        (basic.maritalStatus as
          'NEVER_MARRIED' | 'DIVORCED' | 'WIDOWED' | 'AWAITING_DIVORCE') ??
        'NEVER_MARRIED',
      religion: religion.religion as string,
      caste: religion.caste as string,
      subCaste: (religion.subCaste as string) || null,
      community: (religion.community as string) || null,
      denomination: (religion.denomination as string) || null,
      motherTongue: language.motherTongue as string,
      languagesKnown: toArray(language.languagesKnown),
      // heightCm/highestEducation/profession are null, never a placeholder,
      // when Steps 5/6 are skipped — both are nullable columns precisely so
      // this never has to fake a value (see schema.prisma's comments).
      heightCm: heightCm ?? null,
      weightKg,
      annualIncomeLakhs: annualIncomeLakhs?.toString() ?? null,
      highestEducation: (education.qualification as string) || null,
      educationDetails:
        joinNonEmpty(
          education.college as string,
          education.employmentType as string,
          education.workLocation as string,
        ) ?? null,
      profession: (education.occupation as string) || null,
      employerName: (education.company as string) || null,
      currentCity: location.city as string,
      currentState: location.state as string,
      nativeCity: (location.nativePlace as string) || null,
      country: (location.country as string) || null,
      area: (location.area as string) || null,
      pinCode: (location.pinCode as string) || null,
      bio: (lifestyle.aboutMe as string) || null,
      dietaryHabits: (lifestyle.eatingHabit as string) || null,
      smokingHabits: (lifestyle.smoking as string) || null,
      drinkingHabits: (lifestyle.drinking as string) || null,
      fitness: (lifestyle.fitness as string) || null,
      hobbies: toArray(lifestyle.hobbies),
      physicalStatus:
        joinNonEmpty(
          physical.bloodGroup as string,
          physical.disability as string,
        ) ?? null,
      familyType: (family.familyType as string) || null,
      familyStatus: (family.familyStatus as string) || null,
      familyValues: (family.familyValues as string) || null,
      fatherName: (father.name as string) || null,
      fatherAge: father.age != null ? Number(father.age) : null,
      fatherOccupation: (father.occupation as string) || null,
      motherName: (mother.name as string) || null,
      motherAge: mother.age != null ? Number(mother.age) : null,
      motherOccupation: (mother.occupation as string) || null,
      siblings: siblingDetails.length,
      siblingDetails: siblingDetails as Prisma.InputJsonValue,
      isProfileComplete: true,
      // Placeholder — replaced below with the real, freshly-computed value
      // once photos/partnerPreference/astrology have all been written for
      // this finalize() call.
      profileCompletePct: 0,
    });

    const hasHoroscopeData = Boolean(
      horoscope.birthTime ||
      horoscope.birthPlace ||
      horoscope.rashi ||
      horoscope.nakshatra ||
      horoscope.star ||
      horoscope.horoscopeAvailable,
    );
    const astrologyWrite: Promise<unknown> = hasHoroscopeData
      ? this.profileRepository.upsertAstrologyProfile(userId, {
          birthDate: new Date(basic.dob as string),
          birthTime: (horoscope.birthTime as string) || null,
          birthPlace: (horoscope.birthPlace as string) || null,
          rasi: (horoscope.rashi as string) || null,
          // `star` is a UI duplicate of `nakshatra` in the wizard (both
          // collected, same concept) — nakshatra wins when both are filled.
          nakshatra:
            (horoscope.nakshatra as string) ||
            (horoscope.star as string) ||
            null,
          gotram: (religion.gothra as string) || null,
          dosham: mapDosham(
            horoscope.manglik as string | undefined,
            horoscope.dosham as string | undefined,
          ),
          horoscopeAvailable: Boolean(horoscope.horoscopeAvailable),
        })
      : Promise.resolve();

    const hasPartnerPrefData = Object.keys(partnerPref).length > 0;
    let partnerPrefWrite: Promise<unknown> = Promise.resolve();
    if (hasPartnerPrefData) {
      const [minAge, maxAge] = parseIntRange(
        partnerPref.preferredAgeRange as string | undefined,
        [18, 45],
      );
      const [minHeightCm, maxHeightCm] = parseHeightRangeToCm(
        partnerPref.preferredHeightRange as string | undefined,
        [140, 210],
      );
      partnerPrefWrite = this.profileRepository.upsertPartnerPreference(
        userId,
        {
          minAge,
          maxAge,
          minHeightCm,
          maxHeightCm,
          preferredReligions: toStringArray(
            partnerPref.religionPref as string | undefined,
          ),
          preferredCastes: toStringArray(
            partnerPref.castePref as string | undefined,
          ),
          minIncomeLakhs:
            parseLeadingNumber(
              partnerPref.incomePref as string | undefined,
            )?.toString() ?? null,
          preferredCities: toStringArray(
            partnerPref.locationPref as string | undefined,
          ),
          preferredStates: [],
          preferredEducation: toStringArray(
            partnerPref.educationPref as string | undefined,
          ),
          preferredOccupations: toStringArray(
            partnerPref.occupationPref as string | undefined,
          ),
          preferredMotherTongues: toStringArray(
            partnerPref.motherTonguePref as string | undefined,
          ),
          maritalStatusPref: toStringArray(
            partnerPref.maritalStatusPref as string | undefined,
          ),
          extendedPreferences:
            (partnerPref.extended as Prisma.InputJsonValue | undefined) ?? {},
        },
      );
    }

    const [writtenProfile] = await Promise.all([
      profileWrite,
      astrologyWrite,
      partnerPrefWrite,
    ]);

    // Every matchable field the feed caches — gender, dob, height, religion,
    // caste, community, mother tongue, education, profession, marital status,
    // location, lifestyle — is written here, as are partner preferences. This
    // is the single choke point both finalize() and syncMatchableFromDraft()
    // pass through, so one invalidation covers both. After the writes, never
    // before: dropping the key first would let a concurrent feed request
    // repopulate it from the pre-update rows.
    await this.feedInvalidation.invalidate(userId, 'profile_updated');

    return writtenProfile;
  }

  // Recomputes completion from the real, just-written rows and persists it
  // to UserProfile.profileCompletePct (so other modules querying that column
  // directly — search/matching, once built — see a correct value without
  // going through ProfileService). Returns the same full shape as getOwn()
  // so finalize()'s response is consistent with GET /profiles/me.
  async recalculateAndPersistCompletion(
    userId: string,
    prefetchedProfile?: ProfileEntity,
    prefetchedPhotos?: PhotoEntity[],
    prefetchedDraftData?: Record<string, unknown>,
  ): Promise<ProfileEntity> {
    const full = await this.getOwn(
      userId,
      prefetchedProfile,
      prefetchedPhotos,
      prefetchedDraftData,
    );
    await this.profileRepository.updateProfileCompletePct(
      userId,
      full.completion.percentage,
    );
    // profileCompletePct is a scoring input and part of the cached context, so
    // the stale copy has to go — but only now that the write has succeeded.
    await this.feedInvalidation.invalidate(userId, 'profile_updated');
    full.profileCompletePct = full.completion.percentage;
    return full;
  }

  /**
   * Same as recalculateAndPersistCompletion, but safe to call from anything
   * that isn't itself part of the registration flow — photo upload/delete
   * (see PhotoService), and eventually verification approval/rejection and
   * psychology quiz submission once those modules exist (currently stubs;
   * see modules/verification and the missing psychology module — wire this
   * same call in from wherever their approve/submit action ends up living).
   * getOwn() throws NotFoundException until the mandatory fields are done
   * and UserProfile exists; that's expected here (e.g. a user can upload a
   * photo before finishing Steps 1-4) and must not surface as an error to
   * the caller's own action, which already succeeded.
   */
  async recalculateCompletionIfMaterialized(userId: string): Promise<void> {
    try {
      await this.recalculateAndPersistCompletion(userId);
    } catch (error) {
      if (error instanceof NotFoundException) return;
      this.logger.warn(
        `Completion recalculation skipped for ${userId}: ${(error as Error).message}`,
      );
    }
  }

  /**
   * The mandatory profile fields required for matchmaking — Steps 1-4
   * (Basic/Religion/Language/Location). Physical (Step 6) is skippable and
   * validated separately, finalize-only (see isPhysicalDetailsValid in
   * finalize() above) — it does NOT gate matchability. Returns the list of
   * missing ones (empty === the user is eligible to be
   * materialised/finalised). Single source of truth for both finalize()
   * (throws on missing) and syncMatchableFromDraft() (no-op on missing).
   */
  private missingRequiredFields(
    data: Record<string, Record<string, unknown>>,
  ): string[] {
    const basic = data.basicDetails ?? {};
    const religion = data.religionDetails ?? {};
    const language = data.languageDetails ?? {};
    const location = data.locationDetails ?? {};

    const missing: string[] = [];
    if (!isBasicDetailsComplete(basic)) {
      missing.push(
        'basicDetails (firstName, lastName, gender, maritalStatus, profileCreatedFor, dob)',
      );
    }
    if (!isReligionDetailsComplete(religion)) {
      missing.push('religionDetails (religion, caste, subCaste, community)');
    }
    if (!isLanguageDetailsComplete(language)) {
      missing.push('languageDetails (motherTongue, languagesKnown)');
    }
    if (!isLocationDetailsComplete(location)) {
      missing.push(
        'locationDetails (country, state, city, area, pinCode, nativePlace)',
      );
    }

    return missing;
  }
}
