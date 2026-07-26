import { Module } from '@nestjs/common';
import { StorageModule } from '@app/storage';
import { NotificationsController } from './controllers/notifications.controller';
import { NotificationsService } from './services/notifications.service';
import { NotificationRepository } from './repositories/notification.repository';

/**
 * Notification center + the write path other modules use to raise
 * notifications. PrismaService (@app/database) and RedisService (@app/cache)
 * are global; StorageModule is imported to presign actor avatar URLs.
 *
 * NotificationsService is exported so Interests/Shortlist can create
 * notifications inside their own Prisma transactions (atomic with the domain
 * write) — see NotificationsService.create.
 */
@Module({
  imports: [StorageModule],
  controllers: [NotificationsController],
  providers: [NotificationsService, NotificationRepository],
  exports: [NotificationsService],
})
export class NotificationsModule {}
