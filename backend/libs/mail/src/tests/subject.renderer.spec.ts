import { renderSubject } from '../subject.renderer';
import { EMAIL_TYPE_DEFINITIONS, EmailType } from '../types/email-type.enum';

describe('renderSubject', () => {
  it('interpolates payload values', () => {
    expect(renderSubject('{{code}} is your code', { code: '482910' })).toBe(
      '482910 is your code',
    );
  });

  it('does not HTML-escape — a subject is a header, not markup', () => {
    // Escaping here would show "O&#x27;Brien" in the recipient's inbox list.
    expect(
      renderSubject('Message from {{name}}', { name: "O'Brien & Co" }),
    ).toBe("Message from O'Brien & Co");
  });

  it('strips CR/LF to prevent header injection', () => {
    // The actual threat that escaping would otherwise be covering for: a
    // newline here could inject additional SMTP headers (Bcc, Content-Type).
    const subject = renderSubject('Hi {{name}}', {
      name: 'Asha\r\nBcc: attacker@evil.test',
    });

    expect(subject).not.toMatch(/[\r\n]/);
    expect(subject).toBe('Hi Asha Bcc: attacker@evil.test');
  });

  it('bounds the length so a runaway value cannot produce a huge header', () => {
    expect(renderSubject('{{x}}', { x: 'y'.repeat(5000) })).toHaveLength(200);
  });

  it('renders a missing value as empty rather than throwing', () => {
    // A partially-populated payload should still produce a sendable email.
    expect(renderSubject('Hello {{missing}}!', {})).toBe('Hello !');
  });

  it('produces a non-empty subject for every declared email type', () => {
    const payload = {
      firstName: 'Asha',
      code: '482910',
      senderName: 'Vikram',
      planName: 'Gold',
      renewalDate: '12 Sep 2026',
      matchCount: 3,
    };

    for (const type of Object.values(EmailType)) {
      const subject = renderSubject(
        EMAIL_TYPE_DEFINITIONS[type].subject,
        payload,
      );
      // An empty subject is an instant spam signal.
      expect(subject.length).toBeGreaterThan(3);
    }
  });
});
