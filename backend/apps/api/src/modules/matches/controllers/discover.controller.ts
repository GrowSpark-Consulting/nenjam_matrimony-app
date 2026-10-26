import {
  Body,
  Controller,
  Get,
  Param,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { READ_LIMIT, SEARCH_LIMIT } from '../../../throttling';
import { FeedService } from '../services/feed.service';
import { SearchService } from '../services/search.service';
import { ProfileLookupService } from '../services/profile-lookup.service';
import { PreferencesService } from '../services/preferences.service';
import {
  DiscoverFeedResponseDto,
  DiscoverProfileDetailDto,
} from '../dto/discover-profile.response.dto';
import {
  PartnerPreferenceResponseDto,
  UpdatePartnerPreferenceDto,
} from '../dto/partner-preference.dto';

// Discover surface — feed, partner preferences, and text search. Firebase JWT
// verified by the guard; `userId` is the internal id it resolves, so a caller
// can only read/write their own preferences and never appears in their own
// feed/search results.
@Controller('discover')
@UseGuards(FirebaseAuthGuard)
export class DiscoverController {
  constructor(
    private readonly feedService: FeedService,
    private readonly searchService: SearchService,
    private readonly preferencesService: PreferencesService,
    private readonly profileLookupService: ProfileLookupService,
  ) {}

  // Preference-filtered feed. Same contract as Phase 1 — Flutter is unchanged;
  // the backend alone now decides which profiles match.
  //
  // Rate limited harder than the global default: this endpoint returns other
  // members' profile data a page at a time, so it is the cheapest way to
  // enumerate the entire userbase.
  @Throttle(READ_LIMIT)
  @Get()
  getFeed(
    @CurrentUser('id') userId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('category') category?: string,
    @Query('cursor') cursor?: string,
  ): Promise<DiscoverFeedResponseDto> {
    return this.feedService.getFeed(userId, {
      page: page ? Number(page) : undefined,
      limit: limit ? Number(limit) : undefined,
      category,
      cursor,
    });
  }

  // One profile by member id — see ProfileLookupService for the visibility
  // rules (the feed's own eligibility; 404 for anything not visible). Rate
  // limited like the feed: it also returns another member's profile.
  @Throttle(READ_LIMIT)
  @Get('profiles/:userId')
  getProfile(
    @CurrentUser('id') userId: string,
    @Param('userId') profileUserId: string,
  ): Promise<DiscoverProfileDetailDto> {
    return this.profileLookupService.getVisibleProfile(userId, profileUserId);
  }

  @Get('preferences')
  getPreferences(
    @CurrentUser('id') userId: string,
  ): Promise<PartnerPreferenceResponseDto> {
    return this.preferencesService.get(userId);
  }

  @Put('preferences')
  updatePreferences(
    @CurrentUser('id') userId: string,
    @Body() dto: UpdatePartnerPreferenceDto,
  ): Promise<PartnerPreferenceResponseDto> {
    return this.preferencesService.update(userId, dto);
  }

  // Tightest read limit in the app: arbitrary query text against every
  // member's profile is both the most expensive call here and the most
  // directly useful one to someone harvesting data.
  @Throttle(SEARCH_LIMIT)
  @Get('search')
  search(
    @CurrentUser('id') userId: string,
    @Query('q') q?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ): Promise<DiscoverFeedResponseDto> {
    return this.searchService.search(userId, q ?? '', {
      page: page ? Number(page) : undefined,
      limit: limit ? Number(limit) : undefined,
    });
  }
}
