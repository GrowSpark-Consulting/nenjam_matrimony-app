import { Injectable, NotFoundException } from '@nestjs/common';
import { DiscoverProfileDetailDto } from '../dto/discover-profile.response.dto';
import { buildEligibilityConditions } from '../filters/eligibility.builder';
import { ProfileFeedMapper } from '../mappers/profile-feed.mapper';
import { FeedRepository } from '../repositories/feed.repository';

/**
 * One member's profile, by id, for a viewer — what makes a profile URL
 * survive a browser refresh or be opened from a link.
 *
 * It is not a new way to see profiles. The viewer must pass exactly the
 * eligibility the Discover feed and Search apply (opposite gender, not
 * themselves, not suspended / deactivated / banned / deleted / incomplete,
 * not blocked in either direction, not a declined interest, premium-only
 * visibility honoured), and the row is projected and photo-privacy-filtered by
 * the same select and mapper as the feed. The viewer's *saved partner
 * preferences* are deliberately not applied: someone can legitimately open a
 * profile they reached through a message or an interest that their own
 * filters would not have surfaced.
 *
 * Every refusal is the same 404. A missing id, a deleted or blocked member and
 * an ineligible one are indistinguishable, so this cannot be used to find out
 * whether an account exists.
 */
@Injectable()
export class ProfileLookupService {
  constructor(
    private readonly feedRepository: FeedRepository,
    private readonly mapper: ProfileFeedMapper,
  ) {}

  async getVisibleProfile(
    viewerId: string,
    profileUserId: string,
  ): Promise<DiscoverProfileDetailDto> {
    const notFound = () => new NotFoundException('Profile not available.');
    if (!profileUserId || profileUserId === viewerId) throw notFound();

    const self = await this.feedRepository.findSelf(viewerId);
    const where = {
      AND: [
        ...buildEligibilityConditions({
          currentUserId: viewerId,
          myGender: self?.gender ?? null,
        }),
        { userId: profileUserId },
      ],
    };

    const { rows } = await this.feedRepository.findMatching(
      where,
      { skip: 0, take: 1 },
      viewerId,
    );
    if (rows.length === 0) throw notFound();

    // Detail-only columns are read strictly AFTER the visibility check above
    // has passed, so nothing about a hidden member is ever queried for this
    // viewer, let alone returned.
    const [card, extras] = await Promise.all([
      this.mapper.toDto(rows[0]),
      this.feedRepository.findDetailExtras(profileUserId),
    ]);
    return { ...card, detail: this.mapper.toDetailExtras(extras) };
  }
}
