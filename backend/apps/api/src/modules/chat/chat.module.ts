import { Module } from '@nestjs/common';
import { StorageModule } from '@app/storage';
import { ConversationsController } from './controllers/conversations.controller';
import { MessagesController } from './controllers/messages.controller';
import { AttachmentsController } from './controllers/attachments.controller';
import { ConversationsService } from './services/conversations.service';
import { MessagesService } from './services/messages.service';
import { AttachmentsService } from './services/attachments.service';
import { ChatAttachmentScanner } from './services/chat-attachment-scanner';
import { ChatAuditService } from './services/chat-audit.service';
import { ConversationRepository } from './repositories/conversation.repository';
import { MessageRepository } from './repositories/message.repository';
import { ConversationParticipantGuard } from './guards/conversation-participant.guard';
import { ChatGateway } from './gateways/chat.gateway';
import { ProfileFeedMapper } from '../matches/mappers/profile-feed.mapper';
import { NotificationsModule } from '../notifications/notifications.module';

/**
 * Chat: conversations, messages, attachment upload, and the typing socket
 * handler. RealtimeGateway (message/read push) is global (RealtimeModule);
 * PrismaService/RedisService are global; StorageModule supplies S3Service (for
 * attachment storage + presigned media). ProfileFeedMapper is provided here
 * (own stateless instance) so conversation rows carry the exact Discover card.
 */
@Module({
  imports: [StorageModule, NotificationsModule],
  controllers: [
    ConversationsController,
    MessagesController,
    AttachmentsController,
  ],
  providers: [
    ConversationsService,
    MessagesService,
    AttachmentsService,
    ChatAttachmentScanner,
    ChatAuditService,
    ConversationRepository,
    MessageRepository,
    ConversationParticipantGuard,
    ChatGateway,
    ProfileFeedMapper,
  ],
})
export class ChatModule {}
