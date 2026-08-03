import type { AppConfigService } from '@app/config';
import { TemplateRenderer, htmlToPlainText } from '../template.renderer';
import { EMAIL_TYPE_DEFINITIONS, EmailType } from '../types/email-type.enum';

const configService = {
  mail: {
    provider: 'noop',
    from: 'Nenjam Matrimony <no-reply@example.com>',
    appUrl: 'https://app.example.com',
    supportEmail: 'support@example.com',
    logoUrl: undefined,
  },
} as unknown as AppConfigService;

/** Representative payload per type — enough for every conditional branch. */
const PAYLOADS: Record<EmailType, Record<string, unknown>> = {
  [EmailType.WELCOME]: { firstName: 'Asha' },
  [EmailType.OTP]: { code: '482910', expiryMinutes: 10 },
  [EmailType.VERIFY_EMAIL]: {
    firstName: 'Asha',
    verificationUrl: 'https://app.example.com/verify?t=abc',
    expiryHours: 24,
  },
  [EmailType.FORGOT_PASSWORD]: {
    resetUrl: 'https://app.example.com/reset?t=abc',
    expiryMinutes: 30,
    maskedEmail: 'as***@example.com',
  },
  [EmailType.MATCH_FOUND]: {
    firstName: 'Asha',
    matchName: 'Vikram',
    matchAge: 31,
    matchCity: 'Chennai',
    matchProfession: 'Architect',
    matchProfileUrl: 'https://app.example.com/p/1',
    compatibilityScore: 87,
  },
  [EmailType.PROFILE_VIEWED]: {
    viewCount: 3,
    viewerName: 'Vikram',
    viewedAgo: '2 hours ago',
  },
  [EmailType.NEW_MESSAGE]: {
    senderName: 'Vikram',
    messagePreview: 'Hello, I liked your profile.',
    conversationUrl: 'https://app.example.com/chat/1',
  },
  [EmailType.SUBSCRIPTION]: {
    firstName: 'Asha',
    planName: 'Gold',
    renewalDate: '12 Sep 2026',
    amount: '₹2,999',
  },
  [EmailType.PAYMENT_SUCCESS]: {
    firstName: 'Asha',
    planName: 'Gold',
    amount: '₹2,999',
    validUntil: '12 Sep 2026',
    invoiceId: 'inv_123',
  },
  [EmailType.PAYMENT_FAILED]: {
    planName: 'Gold',
    amount: '₹2,999',
    reason: 'Card declined',
    graceEndsOn: '19 Sep 2026',
    retryUrl: 'https://app.example.com/billing',
  },
  [EmailType.WEEKLY_DIGEST]: {
    firstName: 'Asha',
    matchCount: 2,
    matches: [
      {
        name: 'Vikram',
        age: 31,
        city: 'Chennai',
        profileUrl: 'https://app.example.com/p/1',
      },
      {
        name: 'Rahul',
        age: 33,
        city: 'Bengaluru',
        profileUrl: 'https://app.example.com/p/2',
      },
    ],
  },
  [EmailType.ACCOUNT_SECURITY]: {
    eventDescription: 'Your password was changed.',
    occurredAt: '3 Aug 2026, 11:20',
    device: 'Chrome on Windows',
    location: 'Chennai, IN',
  },
};

describe('TemplateRenderer', () => {
  let renderer: TemplateRenderer;

  beforeAll(() => {
    renderer = new TemplateRenderer(configService);
    renderer.onModuleInit();
  });

  it('compiles a template for every declared EmailType', () => {
    const available = renderer.availableTemplates();
    const required = Object.values(EMAIL_TYPE_DEFINITIONS).map(
      (d) => d.template,
    );
    // Guards the mapping itself: adding an EmailType without its .hbs file is
    // otherwise only discovered when that email first fires in production.
    expect(available).toEqual(expect.arrayContaining(required));
  });

  it.each(Object.values(EmailType))(
    'renders %s into a complete document',
    (type) => {
      const { template } = EMAIL_TYPE_DEFINITIONS[type];
      const html = renderer.render(template, PAYLOADS[type]);

      expect(html).toContain('Nenjam');
      expect(html).toContain('support@example.com');
      // Layout applied — body was wrapped, not returned bare.
      expect(html).toContain('background-color:#FBF9F4');
      // No unresolved handlebars expressions left behind.
      expect(html).not.toMatch(/\{\{/);
    },
  );

  it('escapes HTML in user-supplied values', () => {
    const html = renderer.render('new-message', {
      senderName: '<script>alert("xss")</script>',
      messagePreview: 'hi <img src=x onerror=alert(1)>',
      conversationUrl: 'https://app.example.com/chat/1',
    });

    expect(html).not.toContain('<script>');
    expect(html).not.toContain('onerror=');
    expect(html).toContain('&lt;script&gt;');
  });

  it('omits the unsubscribe link on transactional mail and includes it otherwise', () => {
    const otp = renderer.render('otp', {
      ...PAYLOADS[EmailType.OTP],
      transactional: true,
    });
    const digest = renderer.render('weekly-digest', {
      ...PAYLOADS[EmailType.WEEKLY_DIGEST],
      transactional: false,
    });

    // Offering "unsubscribe" on an OTP would be a promise we cannot keep.
    expect(otp).not.toContain('Manage email preferences');
    expect(digest).toContain('Manage email preferences');
  });

  it('falls back to a wordmark when no logo URL is configured', () => {
    const html = renderer.render('welcome', PAYLOADS[EmailType.WELCOME]);
    expect(html).toContain('Nenjam&nbsp;Matrimony');
    expect(html).not.toContain('<img');
  });

  it('names the unknown template and lists the valid ones', () => {
    expect(() => renderer.render('does-not-exist', {})).toThrow(
      /Unknown email template "does-not-exist".*Available:/s,
    );
  });
});

describe('htmlToPlainText', () => {
  it('keeps link targets so a text reader can still act on the CTA', () => {
    const text = htmlToPlainText(
      '<p>Hi</p><a href="https://x.test/go">Open</a>',
    );
    expect(text).toContain('Open (https://x.test/go)');
  });

  it('drops style blocks rather than dumping CSS into the body', () => {
    const text = htmlToPlainText('<style>.a{color:red}</style><p>Visible</p>');
    expect(text).not.toContain('color:red');
    expect(text).toContain('Visible');
  });

  it('decodes entities so escaped text reads normally in plaintext', () => {
    expect(htmlToPlainText('<p>Tom &amp; Jerry &quot;quoted&quot;</p>')).toBe(
      'Tom & Jerry "quoted"',
    );
  });

  it('produces non-empty text for every rendered template', () => {
    const renderer2 = new TemplateRenderer(configService);
    renderer2.onModuleInit();
    for (const type of Object.values(EmailType)) {
      const { template } = EMAIL_TYPE_DEFINITIONS[type];
      const text = htmlToPlainText(renderer2.render(template, PAYLOADS[type]));
      // An empty plaintext part is a deliverability problem, not a cosmetic one.
      expect(text.length).toBeGreaterThan(40);
    }
  });
});
