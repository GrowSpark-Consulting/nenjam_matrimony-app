import {
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBadRequestResponse,
  ApiBearerAuth,
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
import { BlocksService } from '../services/blocks.service';
import {
  BLOCKED_USERS_PAGE_EXAMPLE,
  BlockedUsersPageDto,
} from '../dto/blocked-user.response.dto';

// Block / unblock a member by their user id, and list who the caller has
// blocked. Every route is user-scoped via the verified Firebase token — a
// caller only ever blocks (or lists their own blocks) on their own behalf.
@ApiTags('Blocks')
@ApiBearerAuth('firebase')
@ApiUnauthorizedResponse({
  description: 'Missing or invalid Firebase ID token.',
})
@Controller('users')
@UseGuards(FirebaseAuthGuard)
export class BlocksController {
  constructor(private readonly blocksService: BlocksService) {}

  // Static path declared before the dynamic `:id/block` routes so Nest's
  // route matching never has to consider shadowing (also a GET vs. POST/
  // DELETE, so there's no actual overlap either way) — same convention as
  // NotificationsController's `read-all`.
  @Get('blocked')
  @ApiOperation({
    summary: 'List blocked members',
    description:
      'The caller’s blocked members, newest-blocked first, as Discover cards ' +
      'plus when each was blocked.',
  })
  @ApiOkResponse({
    description: 'Paginated blocked members.',
    schema: { example: BLOCKED_USERS_PAGE_EXAMPLE },
  })
  listBlocked(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationQueryDto,
  ): Promise<BlockedUsersPageDto> {
    return this.blocksService.listBlocked(userId, pagination);
  }

  @Post(':id/block')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: 'Block a member',
    description:
      'Idempotent — blocking an already-blocked member is a no-op. Removes the ' +
      'member from Discover, Search, Matches (interests/shortlist), and Chat ' +
      'stays gated (existing threads show a blocked banner). Neither side can ' +
      'send interests or messages to the other while the block stands.',
  })
  @ApiParam({ name: 'id', description: 'The member (user) id to block.' })
  @ApiNoContentResponse({ description: 'Blocked (or already blocked).' })
  @ApiBadRequestResponse({ description: 'You cannot block yourself.' })
  @ApiNotFoundResponse({
    description: 'Member not found or no longer available.',
  })
  block(
    @CurrentUser('id') userId: string,
    @Param('id') targetUserId: string,
  ): Promise<void> {
    return this.blocksService.block(userId, targetUserId);
  }

  @Delete(':id/block')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: 'Unblock a member',
    description:
      'Idempotent — unblocking a member who is not blocked is a no-op.',
  })
  @ApiParam({ name: 'id', description: 'The member (user) id to unblock.' })
  @ApiNoContentResponse({ description: 'Unblocked (or was not blocked).' })
  unblock(
    @CurrentUser('id') userId: string,
    @Param('id') targetUserId: string,
  ): Promise<void> {
    return this.blocksService.unblock(userId, targetUserId);
  }
}
