import { OnWorkerEvent, Processor, WorkerHost } from '@nestjs/bullmq';
import { Inject, Injectable, Logger } from '@nestjs/common';
import { Job, UnrecoverableError } from 'bullmq';
import { AppConfigService } from '@app/config';
import { QUEUE_NAMES } from '@app/queue';
import {
  EMAIL_PROVIDER,
  type EmailProvider,
} from '../providers/email-provider.interface';
import { EmailLogRepository } from '../repository/email-log.repository';
import { TemplateRenderer, htmlToPlainText } from '../template.renderer';
import { EMAIL_TYPE_DEFINITIONS } from '../types/email-type.enum';
import {
  EmailSendError,
  type EmailJobData,
  type RenderedEmail,
} from '../interfaces/email.interface';
import { maskEmail } from '../providers/resend.provider';
import { renderSubject } from '../subject.renderer';

/**
 * Consumes the email queue: render -> send -> record.
 *
 * Concurrency of 5 is chosen against Resend's default rate limit (2 req/s on
 * the free tier, higher on paid). Above that the provider starts returning
 * `rate_limit_exceeded`, which is retryable but wasteful; 5 keeps the pipe
 * full without manufacturing 429s. Tune with MAIL_QUEUE_CONCURRENCY.
 */
@Injectable()
@Processor(QUEUE_NAMES.EMAIL, {
  concurrency: Number(process.env.MAIL_QUEUE_CONCURRENCY ?? 5),
})
export class EmailProcessor extends WorkerHost {
  private readonly logger = new Logger(EmailProcessor.name);

  constructor(
    @Inject(EMAIL_PROVIDER) private readonly provider: EmailProvider,
    private readonly renderer: TemplateRenderer,
    private readonly emailLogs: EmailLogRepository,
    private readonly configService: AppConfigService,
  ) {
    super();
  }

  async process(job: Job<EmailJobData>): Promise<{ messageId: string }> {
    const started = Date.now();
    const { emailType, to, emailLogId } = job.data;
    const definition = EMAIL_TYPE_DEFINITIONS[emailType];

    if (!definition) {
      // An enum value that no longer exists — e.g. a job enqueued by an older
      // deploy. Retrying cannot help, so fail terminally rather than five times.
      throw new UnrecoverableError(`Unknown email type "${emailType}".`);
    }

    // attemptsMade is 0-based on the first run.
    const attempt = job.attemptsMade + 1;
    const maxAttempts = job.opts.attempts ?? 1;

    try {
      const email = this.compose(job, definition.template);

      const result = await this.provider.send(email);
      const durationMs = Date.now() - started;

      if (emailLogId) {
        await this.emailLogs.markSent({
          id: emailLogId,
          provider: result.provider,
          providerMessageId: result.messageId,
          attempts: attempt,
          metadata: { emailType, jobId: String(job.id), durationMs },
        });
      }

      // Structured: job id, recipient (masked), template, duration, provider ref.
      this.logger.log(
        JSON.stringify({
          event: 'email.sent',
          jobId: job.id,
          emailType,
          template: definition.template,
          recipient: maskEmail(to),
          provider: result.provider,
          providerMessageId: result.messageId,
          attempt,
          durationMs,
        }),
      );

      return { messageId: result.messageId };
    } catch (error) {
      const durationMs = Date.now() - started;
      const err = error as Error;
      const retryable =
        error instanceof EmailSendError ? error.retryable : true;
      // Terminal when the provider says "this will never work", or when this
      // was the last attempt BullMQ will make.
      const terminal = !retryable || attempt >= maxAttempts;

      if (emailLogId) {
        await this.emailLogs.markFailed({
          id: emailLogId,
          error: err.message,
          attempts: attempt,
          terminal,
          metadata: { emailType, jobId: String(job.id), durationMs, retryable },
        });
      }

      this.logger.error(
        JSON.stringify({
          event: terminal ? 'email.dead_lettered' : 'email.failed',
          jobId: job.id,
          emailType,
          template: definition.template,
          recipient: maskEmail(to),
          attempt,
          maxAttempts,
          retryable,
          durationMs,
          error: err.message,
        }),
      );

      // UnrecoverableError tells BullMQ to skip the remaining attempts. Without
      // it, a permanently-invalid recipient would still consume all 5 and sit
      // in `delayed` for ~2.5 minutes first.
      if (!retryable) {
        throw new UnrecoverableError(err.message);
      }
      // Rethrow so BullMQ applies the configured backoff.
      throw err;
    }
  }

  /** Renders the template and assembles the provider-ready message. */
  private compose(job: Job<EmailJobData>, template: string): RenderedEmail {
    const { to, payload, emailType } = job.data;
    const { from, replyTo } = this.configService.mail;

    const html = this.renderer.render(template, payload);

    return {
      to,
      from,
      replyTo,
      subject: renderSubject(
        EMAIL_TYPE_DEFINITIONS[emailType].subject,
        payload,
      ),
      html,
      text: htmlToPlainText(html),
    };
  }

  @OnWorkerEvent('failed')
  onFailed(job: Job<EmailJobData> | undefined, error: Error): void {
    // Safety net only. process() already logs with full context; this fires
    // for failures outside it (serialisation, a worker-level crash) that would
    // otherwise be silent. Never rethrows — an unhandled listener rejection
    // takes the whole worker down.
    if (!job) {
      this.logger.error(
        `Email job failed before data was available: ${error.message}`,
      );
    }
  }

  @OnWorkerEvent('stalled')
  onStalled(jobId: string): void {
    // A stall means the job was locked but the worker stopped renewing it —
    // usually event-loop starvation or an OOM kill. Worth surfacing loudly
    // because BullMQ silently re-queues it and it looks like a duplicate send.
    this.logger.warn(`Email job ${jobId} stalled and will be reprocessed.`);
  }
}
