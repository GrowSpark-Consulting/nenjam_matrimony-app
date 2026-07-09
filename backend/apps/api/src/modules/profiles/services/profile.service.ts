import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ProfileRepository } from '../repositories/profile.repository';
import { ProfileDraftService } from './profile-draft.service';
import { ProfileEntity } from '../entities/profile.entity';

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

function toStringArray(value: string | undefined): string[] {
  if (!value) return [];
  return value
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean);
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
    private readonly draftService: ProfileDraftService,
  ) {}

  async getOwn(userId: string): Promise<ProfileEntity> {
    const profile = await this.profileRepository.findProfileByUserId(userId);
    if (!profile) {
      throw new NotFoundException('Profile has not been finalized yet.');
    }
    return profile;
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

    const heightCm = parseLeadingNumber(physical.height as string | undefined);
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
      motherTongue: language.motherTongue as string,
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
      bio: (lifestyle.aboutMe as string) || null,
      dietaryHabits: (lifestyle.eatingHabit as string) || null,
      smokingHabits: (lifestyle.smoking as string) || null,
      drinkingHabits: (lifestyle.drinking as string) || null,
      physicalStatus:
        joinNonEmpty(
          physical.bodyType as string,
          physical.complexion as string,
          physical.bloodGroup as string,
          physical.disability as string,
        ) ?? null,
      familyType: (family.familyType as string) || null,
      familyStatus: (family.familyStatus as string) || null,
      fatherOccupation: (family.fatherOccupation as string) || null,
      motherOccupation: (family.motherOccupation as string) || null,
      siblings: brothers + sisters,
      isProfileComplete: true,
      profileCompletePct: 100,
    });

    if (horoscope.birthTime || horoscope.birthPlace || horoscope.rashi) {
      await this.profileRepository.upsertAstrologyProfile(userId, {
        birthDate: new Date(basic.dob as string),
        birthTime: (horoscope.birthTime as string) || null,
        birthPlace: (horoscope.birthPlace as string) || null,
        rasi: (horoscope.rashi as string) || null,
        nakshatra: (horoscope.nakshatra as string) || null,
        gotram: (religion.gothra as string) || null,
        dosham: mapDosham(
          horoscope.manglik as string | undefined,
          horoscope.dosham as string | undefined,
        ),
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
        maritalStatusPref: toStringArray(
          partnerPref.maritalStatusPref as string | undefined,
        ),
      });
    }

    await this.profileRepository.markComplete(userId);
    return profile;
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
