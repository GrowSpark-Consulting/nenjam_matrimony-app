/**
 * For database-gated tests: the member side's REAL ProfileService (its
 * repositories, draft and completion services and LocationService on the
 * test database), behind our `MemberProfileFromDraft`. Only the side
 * effects outside the database are stand-ins: the welcome email, the
 * Discover feed cache and S3 (an accepted client has no photos).
 */
import type { PrismaClient, PrismaService } from '@app/database';
import type { S3Service } from '@app/storage';
import type { FeedInvalidationService } from '../../matches/cache/feed-invalidation.service';
import type { EmailDispatchService } from '../../notifications/services/email-dispatch.service';
import { PhotoRepository } from '../../profiles/repositories/photo.repository';
import { ProfileRepository } from '../../profiles/repositories/profile.repository';
import { RecommendationDismissalRepository } from '../../profiles/repositories/recommendation-dismissal.repository';
import { ProfileCompletionService } from '../../profiles/services/profile-completion.service';
import { ProfileDraftService } from '../../profiles/services/profile-draft.service';
import { ProfileService } from '../../profiles/services/profile.service';
import { LocationService } from '../../reference-data/services/location.service';
import { MemberProfileFromDraft } from '../adapters/platform/member-profile-from-draft';

export function realProfileService(prisma: PrismaClient): ProfileService {
  const db = prisma as unknown as PrismaService;
  const profiles = new ProfileRepository(db);
  const photos = new PhotoRepository(db);
  const completion = new ProfileCompletionService(
    db,
    profiles,
    photos,
    new RecommendationDismissalRepository(db),
  );
  return new ProfileService(
    profiles,
    photos,
    new ProfileDraftService(profiles, completion),
    completion,
    { sendWelcome: () => Promise.resolve() } as unknown as EmailDispatchService,
    {
      invalidate: () => Promise.resolve(),
    } as unknown as FeedInvalidationService,
    {} as S3Service,
    new LocationService(db),
  );
}

export function realMemberProfiles(
  prisma: PrismaClient,
  profiles: Pick<ProfileService, 'syncMatchableFromDraft'> = realProfileService(
    prisma,
  ),
): MemberProfileFromDraft {
  return new MemberProfileFromDraft(prisma, profiles);
}

/** The master-data rows the test client profile's codes name (IN, IN-TN, IN-TN-MADURAI). */
export async function seedClientLocation(prisma: PrismaClient): Promise<void> {
  await prisma.country.create({ data: { code: 'IN', label: 'India' } });
  await prisma.subdivision.create({
    data: {
      code: 'IN-TN',
      countryCode: 'IN',
      label: 'Tamil Nadu',
      type: 'State',
    },
  });
  await prisma.city.create({
    data: {
      code: 'IN-TN-MADURAI',
      stateCode: 'IN-TN',
      countryCode: 'IN',
      label: 'Madurai',
      population: 1_000_000,
    },
  });
}
