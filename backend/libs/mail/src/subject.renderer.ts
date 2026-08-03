import * as Handlebars from 'handlebars';
import type { EmailPayload } from './interfaces/email.interface';

const cache = new Map<string, HandlebarsTemplateDelegate>();

/**
 * Renders a subject line from its Handlebars source in EMAIL_TYPE_DEFINITIONS.
 *
 * Separate from TemplateRenderer because subjects are needed on the *producer*
 * side (MailService writes one to EmailLog when it enqueues), while bodies are
 * only rendered on the *worker* side. Coupling them would drag the whole
 * template directory — and its filesystem dependency — into the API process
 * for no reason.
 *
 * `noEscape` is correct and deliberate here: a subject is a mail header, not
 * HTML, so escaping would turn a name like `O'Brien` into `O&#x27;Brien` in
 * the recipient's inbox list. Header injection is prevented instead by
 * stripping CR/LF from the result, which is the actual threat.
 */
export function renderSubject(source: string, payload: EmailPayload): string {
  let compiled = cache.get(source);
  if (!compiled) {
    compiled = Handlebars.compile(source, { noEscape: true, strict: false });
    cache.set(source, compiled);
  }

  return (
    compiled(payload)
      .replace(/[\r\n]+/g, ' ')
      .trim()
      // RFC 2822 recommends <= 78 chars; clients truncate well before that
      // anyway. Bounded so a runaway payload value can't produce a 4KB header.
      .slice(0, 200)
  );
}
