import { Module, type DynamicModule, Logger } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { AppConfigModule, AppConfigService } from '@app/config';
import { PrismaModule } from '@app/database';
import { QUEUE_NAMES } from '@app/queue';
import { MailService } from './mail.service';
import { EmailQueue } from './queue/email.queue';
import { EmailProcessor } from './queue/email.processor';
import { EmailLogRepository } from './repository/email-log.repository';
import { TemplateRenderer } from './template.renderer';
import {
  EMAIL_PROVIDER,
  type EmailProvider,
} from './providers/email-provider.interface';
import { ResendEmailProvider } from './providers/resend.provider';
import { NoopEmailProvider } from './providers/noop.provider';

/**
 * The single place a concrete provider is chosen.
 *
 * To add AWS SES: write `SesEmailProvider implements EmailProvider`, add a
 * `case 'ses'` below, and extend the `provider` union in configuration.ts.
 * MailService, EmailQueue, EmailProcessor, every controller and every test
 * stay untouched — they only know the EMAIL_PROVIDER token.
 */
const emailProviderFactory = {
  provide: EMAIL_PROVIDER,
  inject: [AppConfigService],
  useFactory: (configService: AppConfigService): EmailProvider => {
    const logger = new Logger('MailModule');
    switch (configService.mail.provider) {
      case 'resend':
        logger.log('Email provider: resend');
        return new ResendEmailProvider(configService);
      case 'noop':
      default:
        logger.warn(
          'Email provider: noop — RESEND_API_KEY is not set, so mail will be rendered and logged but NOT delivered.',
        );
        return new NoopEmailProvider();
    }
  },
};

@Module({})
export class MailModule {
  /**
   * Producer side (API, scheduler). Registers the queue client and MailService
   * but NOT the processor — otherwise every API instance would also start
   * consuming, multiplying concurrency by the number of replicas and sending
   * from a process that has no template directory.
   */
  static forRoot(): DynamicModule {
    return {
      module: MailModule,
      imports: [
        AppConfigModule,
        PrismaModule,
        BullModule.registerQueue({ name: QUEUE_NAMES.EMAIL }),
      ],
      providers: [MailService, EmailQueue, EmailLogRepository],
      exports: [MailService, EmailQueue],
    };
  }

  /**
   * Consumer side (worker only). Everything in forRoot plus the processor,
   * the template renderer and a concrete provider.
   */
  static forWorker(): DynamicModule {
    return {
      module: MailModule,
      imports: [
        AppConfigModule,
        PrismaModule,
        BullModule.registerQueue({ name: QUEUE_NAMES.EMAIL }),
      ],
      providers: [
        MailService,
        EmailQueue,
        EmailLogRepository,
        TemplateRenderer,
        emailProviderFactory,
        EmailProcessor,
      ],
      exports: [MailService, EmailQueue, EMAIL_PROVIDER, TemplateRenderer],
    };
  }
}
