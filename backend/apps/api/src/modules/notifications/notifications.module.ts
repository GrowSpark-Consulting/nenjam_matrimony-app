import { Module } from '@nestjs/common';
import { StorageModule } from '@app/storage';
import { AppConfigModule } from '@app/config';
import { MailModule } from '@app/mail';
import { NotificationsController } from './controllers/notifications.controller';
import { NotificationsService } from './services/notifications.service';
import { PushDispatchService } from './services/push-dispatch.service';
import { EmailDispatchService } from './services/email-dispatch.service';
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
  // AppConfigModule is required explicitly: ConfigModule.forRoot({ isGlobal })
  // inside it makes Nest's own ConfigService global, but AppConfigService is a
  // provider of AppConfigModule itself, which is NOT @Global. Without this
  // import EmailDispatchService cannot resolve it and the API refuses to boot —
  // a failure neither `nest build` nor the unit tests can surface, because
  // builds skip DI and the specs construct the service directly with mocks.
  //
  // MailModule.forRoot() is the producer half — it registers the BullMQ email
  // queue client and MailService, NOT the processor (that lives in the worker).
  imports: [AppConfigModule, StorageModule, MailModule.forRoot()],
  controllers: [NotificationsController],
  providers: [
    NotificationsService,
    NotificationRepository,
    PushDispatchService,
    EmailDispatchService,
  ],
  // EmailDispatchService is exported alongside NotificationsService so domain
  // modules queue email the same way they already raise push — one import,
  // one post-commit call, no direct MailService coupling.
  exports: [NotificationsService, EmailDispatchService],
})
export class NotificationsModule {}
