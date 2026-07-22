import {
  Body,
  Controller,
  Get,
  Put,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { FeedService } from '../services/feed.service';
import { SearchService } from '../services/search.service';
import { PreferencesService } from '../services/preferences.service';
import { DiscoverFeedResponseDto } from '../dto/discover-profile.response.dto';
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
  ) {}

  // Preference-filtered feed. Same contract as Phase 1 — Flutter is unchanged;
  // the backend alone now decides which profiles match.
  @Get()
  getFeed(
    @CurrentUser('id') userId: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('category') category?: string,
  ): Promise<DiscoverFeedResponseDto> {
    return this.feedService.getFeed(userId, {
      page: page ? Number(page) : undefined,
      limit: limit ? Number(limit) : undefined,
      category,
    });
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
