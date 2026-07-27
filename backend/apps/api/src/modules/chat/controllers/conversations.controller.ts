import {
  Body,
  Controller,
  Delete,
  HttpCode,
  HttpStatus,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
  CurrentUser,
  FirebaseAuthGuard,
  PaginationQueryDto,
} from '@app/common';
import { ConversationsService } from '../services/conversations.service';
import { ConversationParticipantGuard } from '../guards/conversation-participant.guard';
import { GetOrCreateConversationDto } from '../dto/get-or-create-conversation.dto';
import { UpdateConversationDto } from '../dto/update-conversation.dto';
import {
  ConversationPageDto,
  GetOrCreateConversationResponseDto,
} from '../dto/conversation.response.dto';

// Conversations. Every route derives the caller from the verified Firebase
// token; `:id` routes additionally pass ConversationParticipantGuard so a
// non-participant can't touch a room they're not in.
@Controller('chat/conversations')
@UseGuards(FirebaseAuthGuard)
export class ConversationsController {
  constructor(private readonly conversationsService: ConversationsService) {}

  /** GET /chat/conversations?page&limit — the caller's conversations, newest
   *  activity first, with last message, unread count, and peer profile. */
  @Get()
  list(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationQueryDto,
  ): Promise<ConversationPageDto> {
    return this.conversationsService.list(userId, pagination);
  }

  /** POST /chat/conversations/get-or-create — open (or create) the thread with
   *  `peerId`. Rejected (403) unless an ACCEPTED interest exists between them. */
  @Post('get-or-create')
  getOrCreate(
    @CurrentUser('id') userId: string,
    @Body() dto: GetOrCreateConversationDto,
  ): Promise<GetOrCreateConversationResponseDto> {
    return this.conversationsService.getOrCreate(userId, dto.peerId);
  }

  /** PATCH /chat/conversations/:id — toggle per-user pin/mute/archive. Only the
   *  flags present in the body change; these are per-caller, never shared. */
  @Patch(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @UseGuards(ConversationParticipantGuard)
  update(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
    @Body() dto: UpdateConversationDto,
  ): Promise<void> {
    return this.conversationsService.updateState(userId, id, {
      isPinned: dto.pinned,
      isMuted: dto.muted,
      isArchived: dto.archived,
    });
  }

  /** POST /chat/conversations/:id/read — mark the peer's messages read. */
  @Post(':id/read')
  @HttpCode(HttpStatus.NO_CONTENT)
  @UseGuards(ConversationParticipantGuard)
  markRead(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ): Promise<void> {
    return this.conversationsService.markRead(userId, id);
  }

  /** POST /chat/conversations/:id/unread — flag the room unread for the caller
   *  (cleared automatically the next time they open it). */
  @Post(':id/unread')
  @HttpCode(HttpStatus.NO_CONTENT)
  @UseGuards(ConversationParticipantGuard)
  markUnread(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ): Promise<void> {
    return this.conversationsService.markUnread(userId, id);
  }

  /** DELETE /chat/conversations/:id — delete the thread for the caller only.
   *  The peer keeps it; it reappears for the caller if a newer message lands. */
  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  @UseGuards(ConversationParticipantGuard)
  remove(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ): Promise<void> {
    return this.conversationsService.deleteForMe(userId, id);
  }

  /** POST /chat/conversations/:id/block — block the room's other participant. */
  @Post(':id/block')
  @HttpCode(HttpStatus.NO_CONTENT)
  @UseGuards(ConversationParticipantGuard)
  block(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ): Promise<void> {
    return this.conversationsService.setBlocked(userId, id, true);
  }

  /** POST /chat/conversations/:id/unblock — unblock the other participant. */
  @Post(':id/unblock')
  @HttpCode(HttpStatus.NO_CONTENT)
  @UseGuards(ConversationParticipantGuard)
  unblock(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ): Promise<void> {
    return this.conversationsService.setBlocked(userId, id, false);
  }
}
