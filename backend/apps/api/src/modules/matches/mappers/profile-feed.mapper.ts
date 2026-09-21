import { Injectable, Logger } from '@nestjs/common';
import { S3Service } from '@app/storage';
import { DiscoverProfileDto } from '../dto/discover-profile.response.dto';
import type { CompatibilityBreakdown } from '../scoring/compatibility.service';
import type { FeedProfileRow } from '../repositories/feed.repository';
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
    const user = (row.user ?? {}) as {
      phone?: string | null;
      photos?: Array<{ id?: string; s3Key: string; isPrimary?: boolean }>;
      faceVerification?: StoredFaceVerification | null;
    };
    const photos = user.photos ?? [];

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
      photoUrls: await this.presignPhotos(photos),
      // Face verification, derived at read time: true only while the photo
      // the live selfie was matched against is still this member's primary
      // photo. Rows selected without faceVerification read as false.
      isVerified: isFaceVerified(user.faceVerification, primaryPhotoOf(photos)),
      isPremium: false,
      isPsychologyCompleted: false,
      isOnline: false,
      horoscopeAvailable: false,
      photoProtected: false,
      phoneVerified: Boolean(user.phone),
      compatibility: {
        // Preference-and-quality compatibility, 0-100. `overallCompatibility`
        // blends both directions (60/40) when the candidate has saved a
        // preference; otherwise it is the one-way score.
        aiMatchPercent: score?.seekerFit ?? 0,
        // Astrology and psychology engines do not exist yet. Left at 0
        // deliberately rather than folded into the number above — a score that
        // silently means something different from its name is worse than a
        // zero that plainly says "not computed".
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
