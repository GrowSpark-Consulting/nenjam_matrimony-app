import { Module } from '@nestjs/common';
import { StorageModule } from '@app/storage';
import { NotificationsController } from './controllers/notifications.controller';
import { NotificationsService } from './services/notifications.service';
import { PushDispatchService } from './services/push-dispatch.service';
import { NotificationRepository } from './repositories/notification.repository';

/**
 * Notification center + the write path other modules use to raise
 * notifications. PrismaService (@app/database) and RedisService (@app/cache)
 * are global; StorageModule is imported to presign actor avatar URLs.
 * FirebaseService (@app/firebase, used by PushDispatchService) is global too.
 *
 * NotificationsService is exported so Interests/Shortlist can create
 * notifications inside their own Prisma transactions (atomic with the domain
 * write) — see NotificationsService.create — and dispatch the matching push
 * once that transaction commits — see NotificationsService.dispatchPush.
 */
@Module({
  imports: [StorageModule],
  controllers: [NotificationsController],
  providers: [
    NotificationsService,
    NotificationRepository,
    PushDispatchService,
  ],
  exports: [NotificationsService],
})
export class NotificationsModule {}
