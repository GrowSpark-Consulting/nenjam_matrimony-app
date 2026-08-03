import { UnrecoverableError, type Job } from 'bullmq';
import type { AppConfigService } from '@app/config';
import { EmailProcessor } from '../queue/email.processor';
import type { EmailLogRepository } from '../repository/email-log.repository';
import type { TemplateRenderer } from '../template.renderer';
import {
  EmailSendError,
  type EmailJobData,
  type RenderedEmail,
  type SendEmailResult,
} from '../interfaces/email.interface';
import { EmailType } from '../types/email-type.enum';

const configService = {
  mail: {
    from: 'Nenjam Matrimony <no-reply@example.com>',
    replyTo: undefined,
  },
} as unknown as AppConfigService;

function makeJob(
  overrides: Partial<Job<EmailJobData>> = {},
): Job<EmailJobData> {
  return {
    id: 'job-1',
    data: {
      emailType: EmailType.OTP,
      to: 'asha@example.com',
      payload: { code: '482910', expiryMinutes: 10 },
      emailLogId: 'log-1',
    },
    attemptsMade: 0,
    opts: { attempts: 5 },
    ...overrides,
  } as Job<EmailJobData>;
}

describe('EmailProcessor', () => {
  // Declared with `send` as a function-typed PROPERTY rather than
  // jest.Mocked<EmailProvider>, whose method signature makes every
  // `expect(provider.send)` trip @typescript-eslint/unbound-method.
  // Fully typed so mock.calls assertions stay type-safe.
  let provider: {
    name: string;
    send: jest.Mock<Promise<SendEmailResult>, [RenderedEmail]>;
  };
  let renderer: jest.Mocked<Pick<TemplateRenderer, 'render'>>;
  let emailLogs: jest.Mocked<
    Pick<EmailLogRepository, 'markSent' | 'markFailed'>
  >;
  let processor: EmailProcessor;

  beforeEach(() => {
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    provider = {
      name: 'mock',
      send: jest
        .fn<Promise<SendEmailResult>, [RenderedEmail]>()
        .mockResolvedValue({ messageId: 'msg-1', provider: 'mock' }),
    };
    renderer = {
      render: jest.fn().mockReturnValue('<p>Your code is 482910</p>'),
    };
    emailLogs = {
      markSent: jest.fn().mockResolvedValue(undefined),
      markFailed: jest.fn().mockResolvedValue(undefined),
    };
    processor = new EmailProcessor(
      provider,
      renderer as unknown as TemplateRenderer,
      emailLogs as unknown as EmailLogRepository,
      configService,
    );
  });

  afterEach(() => jest.restoreAllMocks());

  it('renders, sends and records the provider message id', async () => {
    const result = await processor.process(makeJob());

    expect(renderer.render).toHaveBeenCalledWith(
      'otp',
      expect.objectContaining({ code: '482910' }),
    );
    expect(result).toEqual({ messageId: 'msg-1' });
    expect(emailLogs.markSent).toHaveBeenCalledWith(
      expect.objectContaining({
        id: 'log-1',
        providerMessageId: 'msg-1',
        attempts: 1,
      }),
    );
  });

  it('always supplies a plaintext alternative alongside the HTML', async () => {
    await processor.process(makeJob());
    const sent = provider.send.mock.calls[0][0];

    expect(sent.html).toContain('482910');
    // HTML-only mail scores worse with spam filters.
    expect(sent.text).toContain('482910');
    expect(sent.text).not.toContain('<p>');
  });

  it('resolves the subject from the type definition', async () => {
    await processor.process(makeJob());
    expect(provider.send.mock.calls[0][0].subject).toBe(
      '482910 is your Nenjam Matrimony verification code',
    );
  });

  it('rethrows a retryable failure so BullMQ applies backoff, and marks it non-terminal', async () => {
    provider.send.mockRejectedValue(
      new EmailSendError('rate_limit_exceeded', true, 429),
    );

    await expect(processor.process(makeJob())).rejects.toThrow(
      'rate_limit_exceeded',
    );
    expect(emailLogs.markFailed).toHaveBeenCalledWith(
      expect.objectContaining({ terminal: false, attempts: 1 }),
    );
  });

  it('short-circuits a permanent failure with UnrecoverableError', async () => {
    provider.send.mockRejectedValue(
      new EmailSendError('validation_error: invalid `to`', false, 422),
    );

    // Without this, a malformed recipient would burn all 5 attempts and sit
    // in `delayed` for ~2.5 minutes before reaching the same conclusion.
    await expect(processor.process(makeJob())).rejects.toBeInstanceOf(
      UnrecoverableError,
    );
    expect(emailLogs.markFailed).toHaveBeenCalledWith(
      expect.objectContaining({ terminal: true }),
    );
  });

  it('marks the final retryable attempt terminal so it lands in the DLQ', async () => {
    provider.send.mockRejectedValue(
      new EmailSendError('internal_server_error', true, 500),
    );

    // attemptsMade 4 -> this is attempt 5 of 5.
    await expect(
      processor.process(makeJob({ attemptsMade: 4 })),
    ).rejects.toThrow();
    expect(emailLogs.markFailed).toHaveBeenCalledWith(
      expect.objectContaining({ terminal: true, attempts: 5 }),
    );
  });

  it('treats an unknown email type as unrecoverable rather than retrying five times', async () => {
    const job = makeJob();
    job.data.emailType = 'REMOVED_IN_A_LATER_DEPLOY' as EmailType;

    await expect(processor.process(job)).rejects.toBeInstanceOf(
      UnrecoverableError,
    );
    expect(provider.send).not.toHaveBeenCalled();
  });

  it('surfaces a template failure instead of sending an empty email', async () => {
    renderer.render.mockImplementation(() => {
      throw new Error('Unknown email template "otp".');
    });

    await expect(processor.process(makeJob())).rejects.toThrow(
      /Unknown email template/,
    );
    expect(provider.send).not.toHaveBeenCalled();
  });

  it('proceeds without an EmailLog id — a missing log row must not block delivery', async () => {
    const job = makeJob();
    delete job.data.emailLogId;

    await expect(processor.process(job)).resolves.toEqual({
      messageId: 'msg-1',
    });
    expect(emailLogs.markSent).not.toHaveBeenCalled();
  });

  it('never throws from its worker-event listeners', () => {
    // An unhandled rejection in a listener takes the whole worker process down.
    expect(() =>
      processor.onFailed(undefined, new Error('boom')),
    ).not.toThrow();
    expect(() => processor.onStalled('job-9')).not.toThrow();
  });
});
