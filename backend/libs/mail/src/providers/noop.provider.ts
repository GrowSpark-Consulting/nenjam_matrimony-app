import { Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { EmailProvider } from './email-provider.interface';
import type {
  RenderedEmail,
  SendEmailResult,
} from '../interfaces/email.interface';
import { maskEmail } from './resend.provider';

/**
 * Provider bound when RESEND_API_KEY is absent.
 *
 * Not a stub for its own sake: it is what lets local dev, CI and the test
 * suite exercise the real path — enqueue, worker pickup, template render,
 * EmailLog write — without a third-party secret or a network call. The only
 * thing skipped is the outbound HTTP request, so a template that fails to
 * render still fails here, loudly, exactly as it would in production.
 *
 * `name` is 'noop', which lands in EmailLog.provider — so a row that was never
 * actually delivered is obvious when reading the table later.
 */
@Injectable()
export class NoopEmailProvider implements EmailProvider {
  readonly name = 'noop';

  private readonly logger = new Logger(NoopEmailProvider.name);

  send(email: RenderedEmail): Promise<SendEmailResult> {
    this.logger.log(
      `[noop] would send "${email.subject}" to ${maskEmail(email.to)} ` +
        `(${email.html.length} bytes html, ${email.text.length} bytes text). ` +
        'Set RESEND_API_KEY to deliver for real.',
    );
    return Promise.resolve({
      messageId: `noop_${randomUUID()}`,
      provider: this.name,
    });
  }
}
