import {
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiConflictResponse,
  ApiForbiddenResponse,
  ApiNoContentResponse,
  ApiNotFoundResponse,
  ApiOkResponse,
  ApiOperation,
  ApiParam,
  ApiTags,
  ApiUnauthorizedResponse,
} from '@nestjs/swagger';
import {
  CurrentUser,
  FirebaseAuthGuard,
  PaginationQueryDto,
} from '@app/common';
import { InterestsService } from '../services/interests.service';
import {
  INTEREST_LIST_ITEM_EXAMPLE,
  InterestListItemDto,
} from '../dto/interest-response.dto';

// Read/withdraw side of Interests. The write side (send / accept / decline)
// lives on MatchesController at POST /matches/interest, matching the frontend
// contract (one write endpoint, reused). Every route is user-scoped via the
// verified Firebase token.
@ApiTags('Interests')
@ApiBearerAuth('firebase')
@ApiUnauthorizedResponse({ description: 'Missing or invalid Firebase ID token.' })
@Controller('interests')
@UseGuards(FirebaseAuthGuard)
export class InterestsController {
  constructor(private readonly interestsService: InterestsService) {}

  @Get('received')
  @ApiOperation({
    summary: 'List received interests',
    description:
      'Interests others sent to the caller, newest first. Each item carries the SENDER’s profile card.',
  })
  @ApiOkResponse({
    description: 'Array of received interests.',
    schema: { type: 'array', items: { example: INTEREST_LIST_ITEM_EXAMPLE } },
  })
  received(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationQueryDto,
  ): Promise<InterestListItemDto[]> {
    return this.interestsService.listReceived(userId, pagination);
  }

  @Get('sent')
  @ApiOperation({
    summary: 'List sent interests',
    description:
      'Interests the caller sent, newest first. Each item carries the RECEIVER’s profile card.',
  })
  @ApiOkResponse({
    description: 'Array of sent interests.',
    schema: { type: 'array', items: { example: INTEREST_LIST_ITEM_EXAMPLE } },
  })
  sent(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationQueryDto,
  ): Promise<InterestListItemDto[]> {
    return this.interestsService.listSent(userId, pagination);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: 'Withdraw a sent interest',
    description: 'Deletes a pending interest the caller sent.',
  })
  @ApiParam({ name: 'id', description: 'Interest id to withdraw.' })
  @ApiNoContentResponse({ description: 'Withdrawn.' })
  @ApiForbiddenResponse({ description: 'The interest was not sent by the caller.' })
  @ApiNotFoundResponse({ description: 'Interest not found.' })
  @ApiConflictResponse({ description: 'Interest is no longer pending.' })
  withdraw(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ): Promise<void> {
    return this.interestsService.withdraw(userId, id);
  }
}
