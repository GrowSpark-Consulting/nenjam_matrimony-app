import { Injectable, Logger } from '@nestjs/common';
import { validateSync } from 'class-validator';
import { plainToInstance } from 'class-transformer';
import { AppConfigService } from '@app/config';
import { SendEmailDto } from './dto/send-email.dto';
import { EmailQueue, type EnqueueOptions } from './queue/email.queue';
import { EmailLogRepository } from './repository/email-log.repository';
import { EmailType, EMAIL_TYPE_DEFINITIONS } from './types/email-type.enum';
import type { EmailPayload } from './interfaces/email.interface';
import { renderSubject } from './subject.renderer';

/**
 * The only email API business logic sees.
 *
 * Contract: these methods enqueue and return. They never call a provider,
 * never render a template, and never block on the network — so an HTTP
 * handler's latency is unaffected by how slow Resend is today, and a provider
 * outage degrades into a queue backlog instead of failed user requests.
 *
 * Adding a provider (SES, SendGrid, Postmark) changes nothing in this file.
 */
@Injectable()
export class MailService {
  private readonly logger = new Logger(MailService.name);

  constructor(
    private readonly queue: EmailQueue,
    private readonly emailLogs: EmailLogRepository,
    private readonly configService: AppConfigService,
  ) {}

  // ─── Typed helpers, one per business event ────────────────────────────

  sendOtp(
    to: string,
    params: { code: string; expiryMinutes?: number; userId?: string },
  ) {
    return this.send({
      emailType: EmailType.OTP,
      to,
      userId: params.userId,
      payload: {
        code: params.code,
        expiryMinutes: params.expiryMinutes ?? 10,
        preheader: `Your verification code is ${params.code}`,
      },
    });
  }

  sendWelcome(to: string, params: { firstName: string; userId?: string }) {
    return this.send({
      emailType: EmailType.WELCOME,
      to,
      userId: params.userId,
      payload: {
        firstName: params.firstName,
        preheader: 'Your account is ready — three things worth doing first.',
      },
    });
  }

  sendVerification(
    to: string,
    params: {
      firstName: string;
      verificationUrl: string;
      expiryHours?: number;
      userId?: string;
    },
  ) {
    return this.send({
      emailType: EmailType.VERIFY_EMAIL,
      to,
      userId: params.userId,
      payload: {
        firstName: params.firstName,
        verificationUrl: params.verificationUrl,
        expiryHours: params.expiryHours ?? 24,
        preheader: 'Confirm your email to secure your account.',
      },
    });
  }

  sendForgotPassword(
    to: string,
    params: { resetUrl: string; expiryMinutes?: number; userId?: string },
  ) {
    return this.send({
      emailType: EmailType.FORGOT_PASSWORD,
      to,
      userId: params.userId,
      payload: {
        resetUrl: params.resetUrl,
        expiryMinutes: params.expiryMinutes ?? 30,
        // Masked, not full: this address is rendered into a message that may
        // be forwarded or shoulder-surfed.
        maskedEmail: maskEmailForDisplay(to),
        preheader: 'Reset your password — link expires shortly.',
      },
    });
  }

  sendMatchFound(
    to: string,
    params: {
      firstName: string;
      matchName: string;
      matchAge: number | string;
      matchCity: string;
      matchProfession?: string;
      matchProfileUrl: string;
      compatibilityScore?: number;
      userId?: string;
    },
  ) {
    return this.send({
      emailType: EmailType.MATCH_FOUND,
      to,
      userId: params.userId,
      payload: {
        ...params,
        preheader: `${params.matchName} could be a good match for you.`,
      },
    });
  }

  sendNewMessage(
    to: string,
    params: {
      senderName: string;
      messagePreview: string;
      conversationUrl: string;
      userId?: string;
    },
  ) {
    return this.send({
      emailType: EmailType.NEW_MESSAGE,
      to,
      userId: params.userId,
      payload: {
        ...params,
        // Trimmed here, not in the template: keeps the preview out of the
        // job payload at full length, and Handlebars has no truncate helper.
        messagePreview: truncate(params.messagePreview, 180),
        preheader: `${params.senderName} sent you a message.`,
      },
    });
  }

  sendWeeklyDigest(
    to: string,
    params: {
      firstName: string;
      matchCount: number;
      matches: {
        name: string;
        age: number | string;
        city: string;
        profileUrl: string;
      }[];
      userId?: string;
    },
    options?: EnqueueOptions,
  ) {
    return this.send(
      {
        emailType: EmailType.WEEKLY_DIGEST,
        to,
        userId: params.userId,
        payload: {
          ...params,
          preheader: `${params.matchCount} new ${params.matchCount === 1 ? 'match' : 'matches'} this week.`,
        },
      },
      options,
    );
  }

  // ─── Generic entry point ──────────────────────────────────────────────

  /**
   * Validates, records a QUEUED EmailLog row, and enqueues.
   *
   * The log row is created here rather than in the worker so a job that is
   * never picked up (worker down, Redis flushed) still leaves evidence that
   * the send was requested. Its id rides along on the job so retries update
   * one row instead of writing one per attempt.
   */
  async send(
    input: SendEmailDto,
    options: EnqueueOptions = {},
  ): Promise<string | undefined> {
    const dto = plainToInstance(SendEmailDto, input);
    const errors = validateSync(dto, { whitelist: true });
    if (errors.length > 0) {
      const detail = errors
        .map((e) => Object.values(e.constraints ?? {}).join(', '))
        .join('; ');
      // Throwing beats silently dropping: a caller passing a bad address has
      // a bug, and it should surface at the call site rather than as a
      // dead-lettered job nobody reads.
      throw new Error(`Invalid email request: ${detail}`);
    }

    const definition = EMAIL_TYPE_DEFINITIONS[dto.emailType];
    const payload: EmailPayload = {
      ...(dto.payload ?? {}),
      transactional: definition.transactional,
    };
    const subject = renderSubject(definition.subject, payload);

    const emailLogId = await this.emailLogs.create({
      userId: dto.userId,
      recipient: dto.to,
      subject,
      template: definition.template,
      // Recorded up front so a job stuck in QUEUED still shows its intended
      // provider; the worker overwrites this with whatever actually sent it.
      provider: this.configService.mail.provider,
      metadata: { emailType: dto.emailType },
    });

    await this.queue.enqueue(
      {
        emailType: dto.emailType,
        to: dto.to,
        payload,
        userId: dto.userId,
        emailLogId,
      },
      options,
    );

    return emailLogId;
  }
}

/** `alice@example.com` -> `al***@example.com`. */
export function maskEmailForDisplay(address: string): string {
  const [local, domain] = address.split('@');
  if (!domain) return '***';
  return `${local.slice(0, 2)}${'*'.repeat(Math.max(local.length - 2, 1))}@${domain}`;
}

function truncate(value: string, max: number): string {
  return value.length <= max ? value : `${value.slice(0, max - 1).trimEnd()}…`;
}
