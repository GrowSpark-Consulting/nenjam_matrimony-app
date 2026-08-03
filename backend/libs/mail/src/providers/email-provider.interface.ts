import type {
  RenderedEmail,
  SendEmailResult,
} from '../interfaces/email.interface';

/** DI token. Business logic depends on this, never on a concrete provider. */
export const EMAIL_PROVIDER = Symbol('EMAIL_PROVIDER');

/**
 * The entire surface a transactional email vendor must expose.
 *
 * Kept this small on purpose. Every candidate — Resend, SES, SendGrid,
 * Postmark — can satisfy it, so swapping vendors is one new class plus one
 * line in MailModule's provider factory. Nothing above this interface
 * (MailService, the processor, any caller) changes.
 *
 * Implementations must throw EmailSendError with `retryable` set correctly;
 * that flag is what the worker uses to decide retry vs. dead-letter.
 */
export interface EmailProvider {
  /** Stored on EmailLog.provider, e.g. 'resend'. */
  readonly name: string;

  send(email: RenderedEmail): Promise<SendEmailResult>;
}
