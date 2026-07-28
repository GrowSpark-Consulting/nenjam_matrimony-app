import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { MessagesService } from '../services/messages.service';
import { SendMessageDto } from '../dto/send-message.dto';
import { EditMessageDto } from '../dto/edit-message.dto';
import { MessageListQueryDto } from '../dto/message-list-query.dto';
import { MessageDto, MessagePageDto } from '../dto/message.response.dto';

// Messages. Read/send are authorized inside the service (participant + still
// chat-eligible), since the room id arrives in the query/body rather than as a
// path param.
@Controller('chat/messages')
@UseGuards(FirebaseAuthGuard)
export class MessagesController {
  constructor(private readonly messagesService: MessagesService) {}

  /** GET /chat/messages?conversationId&page&limit — page 1 is the newest slice;
   *  higher pages go further into the past. Pass `cursor` instead of `page` to
   *  use keyset pagination (stable under concurrent inserts); the response's
   *  `nextCursor` is the next page's cursor. */
  @Get()
  list(
    @CurrentUser('id') userId: string,
    @Query() query: MessageListQueryDto,
  ): Promise<MessagePageDto> {
    return this.messagesService.list(userId, query);
  }

  /** POST /chat/messages — send a text/image/audio message. Echoes
   *  `clientMessageId` so the client can reconcile its optimistic bubble. */
  @Post()
  send(
    @CurrentUser('id') userId: string,
    @Body() dto: SendMessageDto,
  ): Promise<MessageDto> {
    return this.messagesService.send(userId, dto);
  }

  /** PATCH /chat/messages/:id — edit your own text message (within the edit
   *  window). Broadcasts the updated message to both participants. */
  @Patch(':id')
  edit(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
    @Body() dto: EditMessageDto,
  ): Promise<MessageDto> {
    return this.messagesService.edit(userId, id, dto.content);
  }

  /** DELETE /chat/messages/:id — delete your own message for everyone (soft
   *  delete). Broadcasts `chat.messageDeleted` to both participants. */
  @Delete(':id')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ): Promise<void> {
    return this.messagesService.remove(userId, id);
  }
}
