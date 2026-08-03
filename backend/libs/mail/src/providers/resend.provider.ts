import { Injectable, Logger } from '@nestjs/common';
import { Resend } from 'resend';
import { AppConfigService } from '@app/config';
import type { EmailProvider } from './email-provider.interface';
import {
  EmailSendError,
  type RenderedEmail,
  type SendEmailResult,
} from '../interfaces/email.interface';

/**
 * Resend error codes that a later attempt could plausibly succeed on.
 *
 * Everything absent from this set is a configuration or payload defect: a bad
 * API key or a malformed recipient fails identically on all 5 attempts, so
 * retrying just delays the dead-letter by ~2.5 minutes and burns quota.
 *
 * Quota codes are deliberately NOT here. `daily_quota_exceeded` resolves on a
 * timescale of hours, far beyond the ~80s the backoff ladder spans, so the
 * honest outcome is to dead-letter immediately and let it be replayed once
 * quota resets — rather than exhaust the retries and land in the same place.
 */
const RETRYABLE_ERROR_CODES = new Set<string>([
  'rate_limit_exceeded',
  'internal_server_error',
  'application_error',
  'concurrent_idempotent_requests',
]);

@Injectable()
export class ResendEmailProvider implements EmailProvider {
  readonly name = 'resend';

  private readonly logger = new Logger(ResendEmailProvider.name);
  private readonly client: Resend;

  constructor(configService: AppConfigService) {
    const apiKey = configService.mail.resendApiKey;
    if (!apiKey) {
      // Unreachable via MailModule (it binds NoopEmailProvider when the key is
      // absent). Guarding anyway so direct instantiation fails loudly rather
      // than constructing a client that 401s on first send.
      throw new Error(
        'ResendEmailProvider requires RESEND_API_KEY. MailModule should bind NoopEmailProvider when it is unset.',
      );
    }
    this.client = new Resend(apiKey);
  }

  async send(email: RenderedEmail): Promise<SendEmailResult> {
    // Resend resolves rather than throws on API errors — a plain try/catch
    // would silently treat a 422 as success.
    const { data, error } = await this.client.emails.send({
      from: email.from,
      to: email.to,
      subject: email.subject,
      html: email.html,
      text: email.text,
      ...(email.replyTo ? { replyTo: email.replyTo } : {}),
    });

    if (error) {
      const retryable = RETRYABLE_ERROR_CODES.has(error.name);
      // error.message is provider copy (e.g. "Invalid `to` field"); it never
      // contains the API key, so it is safe to persist to EmailLog.error.
      this.logger.warn(
        `Resend rejected send to ${maskEmail(email.to)}: ${error.name} — ${error.message} (retryable=${retryable})`,
      );
      throw new EmailSendError(
        `${error.name}: ${error.message}`,
        retryable,
        error.statusCode ?? undefined,
      );
    }

    if (!data?.id) {
      // Shape contract broken — treat as retryable; almost certainly transient.
      throw new EmailSendError(
        'Resend returned neither an error nor a message id.',
        true,
      );
    }

    return { messageId: data.id, provider: this.name };
  }
}

/** Keeps recipient addresses out of logs at full fidelity while staying
 *  useful for support ("was it the gmail one?"). */
export function maskEmail(address: string): string {
  const [local, domain] = address.split('@');
  if (!domain) return '***';
  const head = local.slice(0, 2);
  return `${head}${'*'.repeat(Math.max(local.length - 2, 1))}@${domain}`;
}
