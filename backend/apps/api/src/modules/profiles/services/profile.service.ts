import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import { ProfileRepository } from '../repositories/profile.repository';
import { PhotoRepository } from '../repositories/photo.repository';
import { ProfileDraftService } from './profile-draft.service';
import { ProfileEntity } from '../entities/profile.entity';
import { PhotoEntity } from '../entities/photo.entity';
import { PartnerPreferenceEntity } from '../entities/partner-preference.entity';
import { AstrologyProfileEntity } from '../entities/astrology-profile.entity';
import { ProfileCompletionEntity } from '../entities/profile-completion.entity';

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
  constructor(
    private readonly profileRepository: ProfileRepository,
    private readonly photoRepository: PhotoRepository,
    private readonly draftService: ProfileDraftService,
  ) {}

  // Assembles the full response: the finalized UserProfile plus everything
  // else the profile screen needs in one round trip — photos,
  // partner-preference, astrology (each null/[] if the user never filled
  // that optional section), and a freshly-computed completion breakdown.
  async getOwn(userId: string): Promise<ProfileEntity> {
    const profile = await this.profileRepository.findProfileByUserId(userId);
    if (!profile) {
      throw new NotFoundException('Profile has not been finalized yet.');
    }

    const [photos, partnerPreference, astrology] = await Promise.all([
      this.photoRepository.findAllForUser(userId),
      this.profileRepository.findPartnerPreference(userId),
      this.profileRepository.findAstrologyProfile(userId),
    ]);

    profile.photos = photos;
    profile.partnerPreference = partnerPreference;
    profile.astrology = astrology;
    profile.completion = this.calculateCompletion(
      profile,
      photos,
      partnerPreference,
      astrology,
    );
    return profile;
  }

  // Distinct from ProfileDraftService's completionPercentage (which tracks
  // in-progress wizard draftData before finalize() has ever run). This one
  // reads the finalized row + related tables — the source of truth once a
  // profile exists. basicInfo/religionCommunity/location/careerEducation are
  // enforced by assertRequiredFieldsPresent() at finalize() and so are
  // always complete for any profile that exists at all; the remaining
  // sections are genuinely optional and carry the real signal.
  private calculateCompletion(
    profile: ProfileEntity,
    photos: PhotoEntity[],
    partnerPreference: PartnerPreferenceEntity | null,
    astrology: AstrologyProfileEntity | null,
  ): ProfileCompletionEntity {
    const sections: Record<string, boolean> = {
      basicInfo: Boolean(
        profile.firstName && profile.lastName && profile.dob && profile.gender,
      ),
      religionCommunity: Boolean(profile.religion && profile.caste),
      location: Boolean(profile.currentCity && profile.currentState),
      careerEducation: Boolean(profile.profession && profile.highestEducation),
      about: Boolean(profile.bio && profile.bio.trim().length > 0),
      photos: photos.length > 0,
      partnerPreference: partnerPreference !== null,
      astrology: astrology !== null,
    };

    const completedSections = Object.keys(sections).filter(
      (key) => sections[key],
    );
    const missingSections = Object.keys(sections).filter(
      (key) => !sections[key],
    );
    const total = Object.keys(sections).length;
    const percentage =
      total === 0
        ? 0
        : Math.round((completedSections.length / total) * 100);

    const completion = new ProfileCompletionEntity();
    completion.percentage = percentage;
    completion.completedSections = completedSections;
    completion.missingSections = missingSections;
    return completion;
  }

  // Reads the accumulated wizard draft (see ProfileDraftService) and writes
  // it into UserProfile / AstrologyProfile / PartnerPreference. Fields the
  // Flutter wizard collects but that have no dedicated column in the current
  // schema (e.g. religionDetails.denomination, familyDetails.familyValues)
  // are intentionally left out of the finalized row — they still exist in
  // RegistrationStep.draftData for reference/audit.
  async finalize(userId: string): Promise<ProfileEntity> {
    const draft = await this.draftService.getDraft(userId);
    const data = draft.data as Record<string, Record<string, unknown>>;

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

    this.assertRequiredFieldsPresent(
      basic,
      religion,
      language,
      location,
      education,
      physical,
    );

    const heightCm = parseHeightToCm(physical.height as string | undefined);
    const weightKg = parseLeadingNumber(physical.weight as string | undefined);
    const annualIncomeLakhs = parseLeadingNumber(
      education.annualIncome as string | undefined,
    );
    const brothers = Number(family.brothers ?? 0);
    const sisters = Number(family.sisters ?? 0);

    const profile = await this.profileRepository.upsertProfile(userId, {
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
      heightCm: heightCm ?? 0,
      weightKg,
      annualIncomeLakhs: annualIncomeLakhs?.toString() ?? null,
      highestEducation: education.qualification as string,
      educationDetails:
        joinNonEmpty(
          education.college as string,
          education.employmentType as string,
          education.workLocation as string,
        ) ?? null,
      profession: education.occupation as string,
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
          physical.bodyType as string,
          physical.complexion as string,
          physical.bloodGroup as string,
          physical.disability as string,
        ) ?? null,
      familyType: (family.familyType as string) || null,
      familyStatus: (family.familyStatus as string) || null,
      familyValues: (family.familyValues as string) || null,
      fatherOccupation: (family.fatherOccupation as string) || null,
      motherOccupation: (family.motherOccupation as string) || null,
      siblings: brothers + sisters,
      isProfileComplete: true,
      // Placeholder — replaced below with the real, freshly-computed value
      // once photos/partnerPreference/astrology have all been written for
      // this finalize() call.
      profileCompletePct: 0,
    });

    if (
      horoscope.birthTime ||
      horoscope.birthPlace ||
      horoscope.rashi ||
      horoscope.nakshatra ||
      horoscope.star ||
      horoscope.horoscopeAvailable
    ) {
      await this.profileRepository.upsertAstrologyProfile(userId, {
        birthDate: new Date(basic.dob as string),
        birthTime: (horoscope.birthTime as string) || null,
        birthPlace: (horoscope.birthPlace as string) || null,
        rasi: (horoscope.rashi as string) || null,
        // `star` is a UI duplicate of `nakshatra` in the wizard (both
        // collected, same concept) — nakshatra wins when both are filled.
        nakshatra:
          (horoscope.nakshatra as string) || (horoscope.star as string) || null,
        gotram: (religion.gothra as string) || null,
        dosham: mapDosham(
          horoscope.manglik as string | undefined,
          horoscope.dosham as string | undefined,
        ),
        horoscopeAvailable: Boolean(horoscope.horoscopeAvailable),
      });
    }

    if (Object.keys(partnerPref).length > 0) {
      const [minAge, maxAge] = parseIntRange(
        partnerPref.preferredAgeRange as string | undefined,
        [18, 45],
      );
      const [minHeightCm, maxHeightCm] = parseIntRange(
        partnerPref.preferredHeightRange as string | undefined,
        [140, 210],
      );
      await this.profileRepository.upsertPartnerPreference(userId, {
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
      });
    }

    await this.profileRepository.markComplete(userId);
    return this.recalculateAndPersistCompletion(userId);
  }

  // Recomputes completion from the real, just-written rows and persists it
  // to UserProfile.profileCompletePct (so other modules querying that column
  // directly — search/matching, once built — see a correct value without
  // going through ProfileService). Returns the same full shape as getOwn()
  // so finalize()'s response is consistent with GET /profiles/me.
  async recalculateAndPersistCompletion(userId: string): Promise<ProfileEntity> {
    const full = await this.getOwn(userId);
    await this.profileRepository.updateProfileCompletePct(
      userId,
      full.completion.percentage,
    );
    full.profileCompletePct = full.completion.percentage;
    return full;
  }

  private assertRequiredFieldsPresent(
    basic: Record<string, unknown>,
    religion: Record<string, unknown>,
    language: Record<string, unknown>,
    location: Record<string, unknown>,
    education: Record<string, unknown>,
    physical: Record<string, unknown>,
  ): void {
    const missing: string[] = [];
    if (!basic.firstName) missing.push('basicDetails.firstName');
    if (!basic.lastName) missing.push('basicDetails.lastName');
    if (!basic.gender) missing.push('basicDetails.gender');
    if (!basic.dob) missing.push('basicDetails.dob');
    if (!religion.religion) missing.push('religionDetails.religion');
    if (!religion.caste) missing.push('religionDetails.caste');
    if (!language.motherTongue) missing.push('languageDetails.motherTongue');
    if (!location.city) missing.push('locationDetails.city');
    if (!location.state) missing.push('locationDetails.state');
    if (!education.qualification)
      missing.push('educationDetails.qualification');
    if (!education.occupation) missing.push('educationDetails.occupation');
    if (!physical.height) missing.push('physicalDetails.height');

    if (missing.length > 0) {
      throw new BadRequestException(
        `Cannot finalize profile — missing required fields: ${missing.join(', ')}`,
      );
    }
  }
}
