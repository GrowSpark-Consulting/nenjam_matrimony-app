import { Injectable, Logger } from '@nestjs/common';
import { S3Service } from '@app/storage';
import {
  DiscoverProfileDto,
  ProfileDetailExtrasDto,
} from '../dto/discover-profile.response.dto';
import type { CompatibilityBreakdown } from '../scoring/compatibility.service';
import type {
  FeedProfileRow,
  ProfileDetailExtrasRow,
} from '../repositories/feed.repository';
import {
  arePhotosHidden,
  isPremiumMember,
  type PhotoPrivacyProbes,
} from '../privacy/photo-visibility';
import {
  isFaceVerified,
  primaryPhotoOf,
  type StoredFaceVerification,
} from '../../verification/domain/face-verification-state';

/**
 * Maps a finalized profile row into the display-safe DiscoverProfileDto shared
 * by the feed and search endpoints. Only public fields are exposed — no email,
 * phone number, firebaseUid, or tokens. Photos become short-lived presigned
 * URLs (the bucket is private).
 */
@Injectable()
export class ProfileFeedMapper {
  private readonly logger = new Logger(ProfileFeedMapper.name);

  constructor(private readonly s3: S3Service) {}

  toDtoList(
    rows: FeedProfileRow[],
    scores?: Map<string, CompatibilityBreakdown>,
  ): Promise<DiscoverProfileDto[]> {
    return Promise.all(
      rows.map((row) => this.toDto(row, scores?.get(String(row.userId ?? '')))),
    );
  }

  async toDto(
    row: FeedProfileRow,
    score?: CompatibilityBreakdown,
  ): Promise<DiscoverProfileDto> {
    const user = (row.user ?? {}) as PhotoPrivacyProbes & {
      phone?: string | null;
      photos?: Array<{ id?: string; s3Key: string; isPrimary?: boolean }>;
      faceVerification?: StoredFaceVerification | null;
    };
    const photos = user.photos ?? [];

    // Privacy: a premium member who shows photos only to connections, and
    // this viewer is not one of them. Decided BEFORE signing, so no URL is
    // ever generated for a photo this viewer may not see — withholding them
    // in the client would still have put a working link on the wire.
    //
    // The probes come from `feedProfileSelectFor(viewerId)`; a row selected
    // without them fails closed (see arePhotosHidden).
    const photosHidden = arePhotosHidden(user);
    const visiblePhotos = photosHidden ? [] : photos;

    return {
      id: String(row.userId),
      matrimonyId: String(row.userId).slice(0, 8).toUpperCase(),
      name: `${row.firstName ?? ''} ${row.lastName ?? ''}`.trim(),
      age: this.ageFromDob(row.dob as Date | string | null),
      location: [row.currentCity, row.currentState]
        .filter((p) => typeof p === 'string' && p.length > 0)
        .join(', '),
      profession: (row.profession as string) ?? '',
      education: (row.highestEducation as string) ?? '',
      photoUrls: await this.presignPhotos(visiblePhotos),
      // Face verification, derived at read time: true only while the photo
      // the live selfie was matched against is still this member's primary
      // photo. Rows selected without faceVerification read as false.
      isVerified: isFaceVerified(user.faceVerification, primaryPhotoOf(photos)),
      // From the candidate's own subscription rows, never from anything the
      // client sent.
      isPremium: isPremiumMember(user),
      isPsychologyCompleted: false,
      isOnline: false,
      horoscopeAvailable: false,
      // Tells the client WHY there are no photos, so it can show "photos
      // visible to connections" instead of the generic no-photo placeholder.
      photoProtected: photosHidden,
      phoneVerified: Boolean(user.phone),
      compatibility: {
        // Preference-and-quality compatibility, 0-100. `overallCompatibility`
        // blends both directions (60/40) when the candidate has saved a
        // preference; otherwise it is the one-way score.
        aiMatchPercent: score?.seekerFit ?? 0,
        // No astrology engine exists yet, and `psychologyMatchPercent` is
        // deliberately NOT exposed: both stay at 0.
        //
        // This is a privacy boundary, not a placeholder. The marriage-
        // compatibility quiz only ever affects the ORDER of the feed (via the
        // ranking key — see CompatibilityBreakdown.ranking); every number in
        // this object is the visible score, which is identical with or without
        // quiz data. Surfacing a psychology percentage, or anything derived
        // from it, would let one member read another's quiz answers back out
        // of the app by re-answering and watching the number move. Do not add
        // one without a privacy review.
        // `isPsychologyCompleted` is likewise not populated.
        astroMatchPercent: 0,
        psychologyMatchPercent: 0,
        overallCompatibility: score?.overall ?? 0,
      },
      tags: [],
      religion: (row.religion as string) ?? '',
      caste: (row.caste as string) ?? '',
      community: (row.community as string) ?? '',
      height: this.heightLabel(row.heightCm as number | null),
      diet: (row.dietaryHabits as string) ?? '',
      distanceKm: null,
      gender: String(row.gender ?? '').toLowerCase(),
      profileComplete: Number(row.profileCompletePct ?? 0) >= 100,
      joinedAt: this.isoOrNull(row.createdAt),
      maritalStatus: this.humanizeEnum(row.maritalStatus as string | null),
      motherTongue: (row.motherTongue as string) ?? '',
      smoking: (row.smokingHabits as string) ?? '',
      drinking: (row.drinkingHabits as string) ?? '',
      physicalStatus: (row.physicalStatus as string) ?? '',
      company: (row.employerName as string) ?? '',
      annualIncome: this.incomeLabel(row.annualIncomeLakhs),
      bio: (row.bio as string) ?? '',
      languages: this.toStringArray(row.languagesKnown),
      hobbies: this.toStringArray(row.hobbies),
    };
  }

  /**
   * The detail-only block, exactly as saved. A null row (no profile — not
   * reachable after a visibility check, but typed as possible) maps to the
   * same all-empty shape a member who filled in nothing would get.
   */
  toDetailExtras(row: ProfileDetailExtrasRow | null): ProfileDetailExtrasDto {
    const astro = row?.user?.astrologyProfile ?? null;
    const pref = row?.user?.partnerPreference ?? null;
    const siblings = Array.isArray(row?.siblingDetails)
      ? (row.siblingDetails as Array<{ relation?: unknown }>)
      : [];
    const countOf = (relation: string) =>
      siblings.filter((s) => s?.relation === relation).length;
    const num = (value: unknown): number | null => {
      const n = value == null ? NaN : Number(value);
      return Number.isFinite(n) ? n : null;
    };

    return {
      family: {
        fatherName: row?.fatherName ?? '',
        fatherOccupation: row?.fatherOccupation ?? '',
        motherName: row?.motherName ?? '',
        motherOccupation: row?.motherOccupation ?? '',
        familyType: row?.familyType ?? '',
        familyValues: row?.familyValues ?? '',
        familyStatus: row?.familyStatus ?? '',
        brothers: countOf('BROTHER'),
        sisters: countOf('SISTER'),
      },
      fitness: row?.fitness ?? '',
      horoscope: {
        rasi: astro?.rasi ?? '',
        nakshatra: astro?.nakshatra ?? '',
        dosham:
          astro?.dosham && astro.dosham !== 'NONE'
            ? this.humanizeEnum(astro.dosham)
            : '',
        horoscopeAvailable: astro?.horoscopeAvailable ?? false,
      },
      partnerPreference: pref
        ? {
            minAge: pref.minAge,
            maxAge: pref.maxAge,
            minHeightCm: pref.minHeightCm,
            maxHeightCm: pref.maxHeightCm,
            religions: this.toStringArray(pref.preferredReligions),
            castes: this.toStringArray(pref.preferredCastes),
            education: this.toStringArray(pref.preferredEducation),
            occupations: this.toStringArray(pref.preferredOccupations),
            minIncomeLakhs: num(pref.minIncomeLakhs),
            cities: this.toStringArray(pref.preferredCities),
            states: this.toStringArray(pref.preferredStates),
            motherTongues: this.toStringArray(pref.preferredMotherTongues),
            maritalStatuses: this.toStringArray(pref.maritalStatusPref).map(
              (s) => this.humanizeEnum(s),
            ),
          }
        : null,
    };
  }

  /** A Date (or date string) column -> ISO 8601, or null when absent/invalid. */
  private isoOrNull(value: unknown): string | null {
    if (!(value instanceof Date) && typeof value !== 'string') return null;
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
  }

  /** "NEVER_MARRIED" -> "Never Married". Empty for a null enum. */
  private humanizeEnum(value: string | null): string {
    if (!value) return '';
    return value
      .toLowerCase()
      .split('_')
      .map((w) => (w ? w[0].toUpperCase() + w.slice(1) : w))
      .join(' ');
  }

  /** annualIncomeLakhs (Decimal) -> "12 LPA"; empty when unset/zero. */
  private incomeLabel(value: unknown): string {
    const n = value == null ? NaN : Number(value);
    return Number.isFinite(n) && n > 0 ? `${n} LPA` : '';
  }

  /** Prisma Json array column -> string[]; tolerant of a stray non-array. */
  private toStringArray(value: unknown): string[] {
    if (!Array.isArray(value)) return [];
    return value
      .map((v) => (typeof v === 'string' ? v.trim() : ''))
      .filter((v) => v.length > 0);
  }

  private async presignPhotos(
    photos: Array<{ s3Key: string }>,
  ): Promise<string[]> {
    if (photos.length === 0 || !this.s3.isConfigured()) return [];
    try {
      return await Promise.all(
        photos.map((p) => this.s3.getPresignedGetUrl(p.s3Key)),
      );
    } catch (error) {
      this.logger.warn(
        `Failed to presign feed photos: ${(error as Error).message}`,
      );
      return [];
    }
  }

  private ageFromDob(dob: Date | string | null): number {
    if (!dob) return 0;
    const birth = new Date(dob);
    if (Number.isNaN(birth.getTime())) return 0;
    const now = new Date();
    let age = now.getFullYear() - birth.getFullYear();
    const m = now.getMonth() - birth.getMonth();
    if (m < 0 || (m === 0 && now.getDate() < birth.getDate())) age -= 1;
    return age < 0 ? 0 : age;
  }

  private heightLabel(cm: number | null): string {
    if (!cm || cm <= 0) return '';
    const totalInches = Math.round(cm / 2.54);
    const feet = Math.floor(totalInches / 12);
    const inches = totalInches % 12;
    return `${feet}'${inches}"`;
  }
}
