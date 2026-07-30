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
import { PushDispatchService } from '../services/push-dispatch.service';
import {
  NOTIFICATIONS_PAGE_EXAMPLE,
  NotificationsPageDto,
  UnreadCountDto,
} from '../dto/notification-response.dto';
import {
  RegisterDeviceDto,
  UnregisterDeviceDto,
} from '../dto/device-token.dto';

// Notification center. Every route is user-scoped via the verified Firebase
// token — a caller only ever sees or mutates their own notifications.
@ApiTags('Notifications')
@ApiBearerAuth('firebase')
@ApiUnauthorizedResponse({ description: 'Missing or invalid Firebase ID token.' })
@Controller('notifications')
@UseGuards(FirebaseAuthGuard)
export class NotificationsController {
  constructor(
    private readonly notificationsService: NotificationsService,
    private readonly pushDispatchService: PushDispatchService,
  ) {}

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

  @Post('device')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: 'Register a device for push notifications',
    description:
      "Registers (or reactivates) an FCM token for the calling user's device. Idempotent — re-registering the same token retargets/reactivates it.",
  })
  @ApiNoContentResponse({ description: 'Registered.' })
  registerDevice(
    @CurrentUser('id') userId: string,
    @Body() dto: RegisterDeviceDto,
  ): Promise<void> {
    return this.pushDispatchService.registerDevice(
      userId,
      dto.fcmToken,
      dto.platform,
    );
  }

  @Delete('device')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: 'Unregister a device from push notifications',
    description:
      "`fcmToken` is sent in the request body (matching DELETE /matches/shortlist). Scoped to the caller's own devices — deactivating a token that is not theirs (or does not exist) is a silent no-op.",
  })
  @ApiNoContentResponse({ description: 'Deactivated (or was not registered).' })
  unregisterDevice(
    @CurrentUser('id') userId: string,
    @Body() dto: UnregisterDeviceDto,
  ): Promise<void> {
    return this.pushDispatchService.unregisterDevice(userId, dto.fcmToken);
  }

  @Post('test')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({
    summary: 'Send a test push notification',
    description:
      "Sends a test push to the caller's most-recently-registered active device.",
  })
  @ApiNoContentResponse({ description: 'Test push sent.' })
  @ApiNotFoundResponse({ description: 'No registered device for this user.' })
  sendTestPush(@CurrentUser('id') userId: string): Promise<void> {
    return this.pushDispatchService.sendTestToLatestDevice(userId);
  }
}
