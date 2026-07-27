import { Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser, FirebaseAuthGuard } from '@app/common';
import { MessagesService } from '../services/messages.service';
import { SendMessageDto } from '../dto/send-message.dto';
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
}
