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
  CurrentUser,
  FirebaseAuthGuard,
  PaginationQueryDto,
} from '@app/common';
import { NotificationsService } from '../services/notifications.service';
import {
  NotificationsPageDto,
  UnreadCountDto,
} from '../dto/notification-response.dto';

// Notification center. Every route is user-scoped via the verified Firebase
// token — a caller only ever sees or mutates their own notifications.
@Controller('notifications')
@UseGuards(FirebaseAuthGuard)
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  /** GET /notifications?page&limit — paginated, newest first. */
  @Get()
  list(
    @CurrentUser('id') userId: string,
    @Query() pagination: PaginationQueryDto,
  ): Promise<NotificationsPageDto> {
    return this.notificationsService.list(userId, pagination);
  }

  /** GET /notifications/unread-count — the bell badge value (Redis cached). */
  @Get('unread-count')
  async unreadCount(
    @CurrentUser('id') userId: string,
  ): Promise<UnreadCountDto> {
    return { count: await this.notificationsService.getUnreadCount(userId) };
  }

  /** PATCH /notifications/read-all — mark every notification read. Declared
   *  before the parameterised route so it can never be shadowed by `:id`. */
  @Patch('read-all')
  @HttpCode(HttpStatus.NO_CONTENT)
  markAllRead(@CurrentUser('id') userId: string): Promise<void> {
    return this.notificationsService.markAllRead(userId);
  }

  /** PATCH /notifications/:id/read — mark one read (404 if not the caller's). */
  @Patch(':id/read')
  @HttpCode(HttpStatus.NO_CONTENT)
  markRead(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ): Promise<void> {
    return this.notificationsService.markRead(userId, id);
  }
}
