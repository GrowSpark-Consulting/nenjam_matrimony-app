import {
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Query,
  UseGuards,
} from '@nestjs/common';
import {
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
import { NotificationsService } from '../services/notifications.service';
import {
  NOTIFICATIONS_PAGE_EXAMPLE,
  NotificationsPageDto,
  UnreadCountDto,
} from '../dto/notification-response.dto';

// Notification center. Every route is user-scoped via the verified Firebase
// token — a caller only ever sees or mutates their own notifications.
@ApiTags('Notifications')
@ApiBearerAuth('firebase')
@ApiUnauthorizedResponse({ description: 'Missing or invalid Firebase ID token.' })
@Controller('notifications')
@UseGuards(FirebaseAuthGuard)
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Get()
  @ApiOperation({
    summary: 'List notifications',
    description: 'Paginated notification center, newest first.',
  })
  @ApiOkResponse({
    description: 'Paginated notifications.',
    schema: { example: NOTIFICATIONS_PAGE_EXAMPLE },
  })
  list(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationQueryDto,
  ): Promise<NotificationsPageDto> {
    return this.notificationsService.list(userId, pagination);
  }

  @Get('unread-count')
  @ApiOperation({
    summary: 'Unread notification count',
    description: 'The bell-badge value. Redis-cached with automatic invalidation.',
  })
  @ApiOkResponse({ description: 'Unread count.', schema: { example: { count: 3 } } })
  async unreadCount(
    @CurrentUser('id') userId: string,
  ): Promise<UnreadCountDto> {
    return { count: await this.notificationsService.getUnreadCount(userId) };
  }

  @Patch('read-all')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Mark all notifications read' })
  @ApiNoContentResponse({ description: 'All marked read.' })
  markAllRead(@CurrentUser('id') userId: string): Promise<void> {
    // Declared before `:id/read` so the static path is never shadowed.
    return this.notificationsService.markAllRead(userId);
  }

  @Patch(':id/read')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Mark one notification read' })
  @ApiParam({ name: 'id', description: 'Notification id.' })
  @ApiNoContentResponse({ description: 'Marked read (idempotent).' })
  @ApiNotFoundResponse({ description: 'Notification not found for this user.' })
  markRead(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ): Promise<void> {
    return this.notificationsService.markRead(userId, id);
  }
}
