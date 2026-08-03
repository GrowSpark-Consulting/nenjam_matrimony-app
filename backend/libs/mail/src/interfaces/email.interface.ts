import type { EmailType } from '../types/email-type.enum';

/**
 * A fully-resolved message, ready for a provider. Produced by the worker after
 * template rendering; providers never see an EmailType or a template name.
 */
export interface RenderedEmail {
  to: string;
  from: string;
  replyTo?: string;
  subject: string;
  html: string;
  /** Auto-derived plaintext alternative. Spam filters penalise HTML-only mail. */
  text: string;
}

/** What a provider reports back. Deliberately minimal — the union of what
 *  Resend, SES, SendGrid and Postmark all return. */
export interface SendEmailResult {
  /** Provider-side id, stored on EmailLog for dashboard/webhook correlation. */
  messageId: string;
  /** Identifier persisted to EmailLog.provider, e.g. 'resend'. */
  provider: string;
}

/**
 * The payload handed to a template. Values are escaped by Handlebars on
 * render — see TemplateRenderer for the one deliberate exception.
 */
export type EmailPayload = Record<string, unknown>;

/** The BullMQ job body. Must stay JSON-serialisable: BullMQ round-trips it
 *  through Redis, so no Date objects, class instances or functions. */
export interface EmailJobData {
  emailType: EmailType;
  to: string;
  payload: EmailPayload;
  /** Nullable — verification mail can precede a User row. */
  userId?: string;
  /** Set by MailService so a retry reuses the same EmailLog row rather than
   *  writing a new one per attempt. */
  emailLogId?: string;
}

/**
 * Classifies a provider failure so the worker can decide whether to retry.
 *
 * The distinction is what keeps the queue healthy: a 422 for a malformed
 * recipient will fail identically on all 5 attempts and should go straight to
 * the DLQ, while a 429 or a 5xx is exactly what backoff exists for.
 */
export class EmailSendError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean,
    readonly statusCode?: number,
  ) {
    super(message);
    this.name = 'EmailSendError';
  }
}
