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
import {
  CurrentUser,
  FirebaseAuthGuard,
  PaginationQueryDto,
} from '@app/common';
import { InterestsService } from '../../interests/services/interests.service';
import { MatchInterestDto } from '../../interests/dto/match-interest.dto';
import { SendInterestResponseDto } from '../../interests/dto/interest-response.dto';
import { ShortlistService } from '../services/shortlist.service';
import { ShortlistProfileDto } from '../dto/shortlist.dto';
import { DiscoverProfileDto } from '../dto/discover-profile.response.dto';

/**
 * Write side of Matches: the interest send/respond endpoint and shortlist
 * add/remove/list. These paths (`/matches/interest`, `/matches/shortlist`) are
 * the exact ones the Flutter mock repositories target, so cutover is a one-line
 * provider swap on the client. The interest business logic lives in
 * InterestsService (owned by InterestsModule); this controller only routes.
 */
@Controller('matches')
@UseGuards(FirebaseAuthGuard)
export class MatchesController {
  constructor(
    private readonly interestsService: InterestsService,
    private readonly shortlistService: ShortlistService,
  ) {}

  /**
   * POST /matches/interest — polymorphic:
   *   { profileId }            → send an interest (returns { id, sentAt, status })
   *   { interestId, accept }   → accept/decline a received interest
   */
  @Post('interest')
  interest(
    @CurrentUser('id') userId: string,
    @Body() dto: MatchInterestDto,
  ): Promise<SendInterestResponseDto> {
    return this.interestsService.dispatchMatchInterest(userId, dto);
  }

  /** GET /matches/shortlist?page&limit — the caller's shortlisted profiles. */
  @Get('shortlist')
  listShortlist(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationQueryDto,
  ): Promise<DiscoverProfileDto[]> {
    return this.shortlistService.list(userId, pagination);
  }

  /** POST /matches/shortlist — add a profile to the shortlist (idempotent). */
  @Post('shortlist')
  @HttpCode(HttpStatus.NO_CONTENT)
  addShortlist(
    @CurrentUser('id') userId: string,
    @Body() dto: ShortlistProfileDto,
  ): Promise<void> {
    return this.shortlistService.add(userId, dto.profileId);
  }

  /** DELETE /matches/shortlist — remove a profile from the shortlist
   *  (idempotent). `profileId` is sent in the body, matching the client. */
  @Delete('shortlist')
  @HttpCode(HttpStatus.NO_CONTENT)
  removeShortlist(
    @CurrentUser('id') userId: string,
    @Body() dto: ShortlistProfileDto,
  ): Promise<void> {
    return this.shortlistService.remove(userId, dto.profileId);
  }
}
