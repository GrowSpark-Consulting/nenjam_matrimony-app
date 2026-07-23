import { Injectable, Logger } from '@nestjs/common';
import { S3Service } from '@app/storage';
import { DiscoverProfileDto } from '../dto/discover-profile.response.dto';
import type { FeedProfileRow } from '../repositories/feed.repository';

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

  toDtoList(rows: FeedProfileRow[]): Promise<DiscoverProfileDto[]> {
    return Promise.all(rows.map((row) => this.toDto(row)));
  }

  async toDto(row: FeedProfileRow): Promise<DiscoverProfileDto> {
    const user = (row.user ?? {}) as {
      phone?: string | null;
      photos?: Array<{ s3Key: string }>;
    };

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
      photoUrls: await this.presignPhotos(user.photos ?? []),
      // Phase 3+: derive from KycVerification/FaceVerification + UserSubscription.
      isVerified: false,
      isPremium: false,
      isPsychologyCompleted: false,
      isOnline: false,
      horoscopeAvailable: false,
      photoProtected: false,
      phoneVerified: Boolean(user.phone),
      compatibility: {
        aiMatchPercent: 0,
        astroMatchPercent: 0,
        psychologyMatchPercent: 0,
        overallCompatibility: 0,
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
    };
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
