import type { AppConfigService } from '@app/config';
import {
  EmailSendError,
  type RenderedEmail,
} from '../interfaces/email.interface';

/** Typed payload so assertions on `mock.calls` are not `any`. */
type ResendPayload = Record<string, unknown>;
const sendMock = jest.fn<Promise<unknown>, [ResendPayload]>();

// Mocked so the suite never performs a network call and needs no API key.
jest.mock('resend', () => ({
  Resend: jest.fn().mockImplementation(() => ({ emails: { send: sendMock } })),
}));

// Imported after the mock is registered.
import { ResendEmailProvider, maskEmail } from '../providers/resend.provider';

const configWithKey = {
  mail: { resendApiKey: 're_test_key_placeholder' },
} as unknown as AppConfigService;

const email: RenderedEmail = {
  to: 'asha@example.com',
  from: 'Nenjam Matrimony <no-reply@example.com>',
  subject: 'Your code',
  html: '<p>482910</p>',
  text: '482910',
};

describe('ResendEmailProvider', () => {
  beforeEach(() => {
    sendMock.mockReset();
    jest.spyOn(console, 'warn').mockImplementation(() => undefined);
  });
  afterEach(() => jest.restoreAllMocks());

  it('returns the provider message id on success', async () => {
    sendMock.mockResolvedValue({ data: { id: 'resend-abc' }, error: null });

    const result = await new ResendEmailProvider(configWithKey).send(email);

    expect(result).toEqual({ messageId: 'resend-abc', provider: 'resend' });
  });

  it('omits replyTo entirely when unset rather than sending undefined', async () => {
    sendMock.mockResolvedValue({ data: { id: 'x' }, error: null });
    await new ResendEmailProvider(configWithKey).send(email);

    expect(sendMock.mock.calls[0][0]).not.toHaveProperty('replyTo');
  });

  it('passes replyTo through when configured', async () => {
    sendMock.mockResolvedValue({ data: { id: 'x' }, error: null });
    await new ResendEmailProvider(configWithKey).send({
      ...email,
      replyTo: 'hi@example.com',
    });

    expect(sendMock.mock.calls[0][0].replyTo).toBe('hi@example.com');
  });

  it('throws rather than reporting success — Resend resolves on API errors', async () => {
    // The trap this guards: Resend returns { data: null, error } instead of
    // rejecting, so a plain try/catch would record a 422 as a delivered email.
    sendMock.mockResolvedValue({
      data: null,
      error: {
        name: 'validation_error',
        message: 'Invalid `to` field',
        statusCode: 422,
      },
    });

    await expect(
      new ResendEmailProvider(configWithKey).send(email),
    ).rejects.toBeInstanceOf(EmailSendError);
  });

  it.each([
    ['rate_limit_exceeded', 429, true],
    ['internal_server_error', 500, true],
    ['application_error', 500, true],
    ['validation_error', 422, false],
    ['invalid_api_key', 401, false],
    ['missing_api_key', 401, false],
    ['invalid_from_address', 403, false],
    ['not_found', 404, false],
    // Quota resolves over hours, far beyond the ~80s backoff ladder — so it
    // is classified non-retryable and dead-lettered for later replay.
    ['daily_quota_exceeded', 429, false],
  ])('classifies %s as retryable=%s', async (name, statusCode, retryable) => {
    sendMock.mockResolvedValue({
      data: null,
      error: { name, message: 'x', statusCode },
    });

    await new ResendEmailProvider(configWithKey)
      .send(email)
      .catch((error: EmailSendError) => {
        expect(error.retryable).toBe(retryable);
        expect(error.statusCode).toBe(statusCode);
      });
    expect.assertions(2);
  });

  it('treats a malformed success response as retryable', async () => {
    sendMock.mockResolvedValue({ data: null, error: null });

    await expect(
      new ResendEmailProvider(configWithKey).send(email),
    ).rejects.toMatchObject({
      retryable: true,
    });
  });

  it('refuses to construct without an API key instead of 401ing on first send', () => {
    const noKey = {
      mail: { resendApiKey: undefined },
    } as unknown as AppConfigService;
    expect(() => new ResendEmailProvider(noKey)).toThrow(/RESEND_API_KEY/);
  });

  it('never logs the recipient at full fidelity', async () => {
    const warn = jest.spyOn(console, 'warn');
    sendMock.mockResolvedValue({
      data: null,
      error: { name: 'validation_error', message: 'bad', statusCode: 422 },
    });

    await new ResendEmailProvider(configWithKey)
      .send(email)
      .catch(() => undefined);

    const logged = warn.mock.calls.flat().join(' ');
    expect(logged).not.toContain('asha@example.com');
  });
});

describe('maskEmail', () => {
  it.each([
    ['asha@example.com', 'as**@example.com'],
    ['a@b.io', 'a*@b.io'],
    ['garbage', '***'],
  ])('masks %s', (input, expected) => {
    expect(maskEmail(input)).toBe(expected);
  });
});
