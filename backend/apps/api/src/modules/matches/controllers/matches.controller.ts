import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { READ_LIMIT, WRITE_LIMIT } from '../../../throttling';
import {
  ApiBearerAuth,
  ApiBody,
  ApiConflictResponse,
  ApiCreatedResponse,
  ApiForbiddenResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import {
  CurrentUser,
  FirebaseAuthGuard,
  PaginationQueryDto,
} from '@app/common';
import { InterestsService } from '../../interests/services/interests.service';
import { MatchInterestDto } from '../../interests/dto/match-interest.dto';
import {
  DISCOVER_PROFILE_EXAMPLE,
  SEND_INTEREST_RESPONSE_EXAMPLE,
  SendInterestResponseDto,
} from '../../interests/dto/interest-response.dto';
import { ShortlistService } from '../services/shortlist.service';
import { ShortlistProfileDto } from '../dto/shortlist.dto';
import { ProfileViewService } from '../services/profile-view.service';
import {
  PROFILE_VIEWER_EXAMPLE,
  ProfileViewerDto,
  RecordProfileViewDto,
} from '../dto/profile-view.dto';
import { DiscoverProfileDto } from '../dto/discover-profile.response.dto';

/**
 * Write side of Matches: the interest send/respond endpoint and shortlist
 * add/remove/list. These paths (`/matches/interest`, `/matches/shortlist`) are
 * the exact ones the Flutter mock repositories target, so cutover is a one-line
 * provider swap on the client. The interest business logic lives in
 * InterestsService (owned by InterestsModule); this controller only routes.
 */
@ApiBearerAuth('firebase')
@ApiUnauthorizedResponse({
  description: 'Missing or invalid Firebase ID token.',
})
@Controller('matches')
@UseGuards(FirebaseAuthGuard)
export class MatchesController {
  constructor(
    private readonly interestsService: InterestsService,
    private readonly shortlistService: ShortlistService,
    private readonly profileViewService: ProfileViewService,
  ) {}

  // Interest spam is the abuse this guards against: without a limit a script
  // can send one to every member on the platform in a few seconds.
  @Throttle(WRITE_LIMIT)
  @Post('interest')
  @ApiTags('Interests')
  @ApiOperation({
    summary: 'Send or respond to an interest',
    description:
      'Polymorphic: `{ profileId }` sends an interest; `{ interestId, accept }` ' +
      'accepts (true) or declines (false) a received one. Both are atomic with ' +
      'the resulting notification and are idempotent / race-safe.',
  })
  @ApiBody({
    type: MatchInterestDto,
    examples: {
      send: {
        summary: 'Send',
        value: { profileId: DISCOVER_PROFILE_EXAMPLE.id },
      },
      respond: {
        summary: 'Accept / decline',
        value: { interestId: SEND_INTEREST_RESPONSE_EXAMPLE.id, accept: true },
      },
    },
  })
  @ApiCreatedResponse({
    description: 'The created/updated interest record.',
    schema: { example: SEND_INTEREST_RESPONSE_EXAMPLE },
  })
  @ApiForbiddenResponse({
    description: 'Blocked, suspended receiver, or sender profile incomplete.',
  })
  @ApiNotFoundResponse({
    description: 'Receiver/interest not found or unavailable.',
  })
  @ApiConflictResponse({ description: 'Duplicate or reverse active interest.' })
  interest(
    @CurrentUser('id') userId: string,
    @Body() dto: MatchInterestDto,
  ): Promise<SendInterestResponseDto> {
    return this.interestsService.dispatchMatchInterest(userId, dto);
  }

  @Get('shortlist')
  @ApiTags('Shortlist')
  @ApiOperation({
    summary: 'List shortlisted profiles',
    description:
      'The caller’s shortlisted profiles as Discover cards, newest first.',
  })
  @ApiOkResponse({
    description: 'Array of shortlisted profiles (Discover card shape).',
    schema: { type: 'array', items: { example: DISCOVER_PROFILE_EXAMPLE } },
  })
  listShortlist(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationQueryDto,
  ): Promise<DiscoverProfileDto[]> {
    return this.shortlistService.list(userId, pagination);
  }

  @Throttle(WRITE_LIMIT)
  @Post('shortlist')
  @ApiTags('Shortlist')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: 'Add to shortlist',
    description: 'Idempotent — re-adding an existing entry is a no-op.',
  })
  @ApiNoContentResponse({ description: 'Added (or already present).' })
  @ApiNotFoundResponse({ description: 'Target member is unavailable.' })
  addShortlist(
    @CurrentUser('id') userId: string,
    @Body() dto: ShortlistProfileDto,
  ): Promise<void> {
    return this.shortlistService.add(userId, dto.profileId);
  }

  @Delete('shortlist')
  @ApiTags('Shortlist')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: 'Remove from shortlist',
    description:
      'Idempotent. `profileId` is sent in the request body, matching the client.',
  })
  @ApiNoContentResponse({ description: 'Removed (or was not present).' })
  removeShortlist(
    @CurrentUser('id') userId: string,
    @Body() dto: ShortlistProfileDto,
  ): Promise<void> {
    return this.shortlistService.remove(userId, dto.profileId);
  }

  @Get('profile-views')
  @ApiTags('Profile Views')
  @ApiOperation({
    summary: 'List members who viewed my profile',
    description:
      'Distinct viewers, most recently seen first. Repeat views by the same ' +
      'member collapse to one entry carrying their latest `viewedAt`.',
  })
  @ApiOkResponse({
    description: 'Array of viewers (Discover card + view timestamp).',
    schema: { type: 'array', items: { example: PROFILE_VIEWER_EXAMPLE } },
  })
  listProfileViewers(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationQueryDto,
  ): Promise<ProfileViewerDto[]> {
    return this.profileViewService.listViewers(userId, pagination);
  }

  // Fires on every profile open, so this gets the read tier rather than the
  // write one — it is frequent by design, not abusive by nature.
  @Throttle(READ_LIMIT)
  @Post('profile-view')
  @ApiTags('Profile Views')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: 'Record a profile view',
    description:
      'Called when the caller opens someone else’s profile. Always logs the ' +
      'view; raises a PROFILE_VIEW notification only on the first view by ' +
      'that member within the throttle window. Views across a block are ' +
      'silently ignored.',
  })
  @ApiNoContentResponse({ description: 'Recorded (or softly ignored).' })
  @ApiNotFoundResponse({ description: 'Target member is unavailable.' })
  recordProfileView(
    @CurrentUser('id') userId: string,
    @Body() dto: RecordProfileViewDto,
  ): Promise<void> {
    return this.profileViewService.record(userId, dto.profileId);
  }
}
