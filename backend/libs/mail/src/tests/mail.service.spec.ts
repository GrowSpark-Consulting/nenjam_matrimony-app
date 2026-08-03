import type { AppConfigService } from '@app/config';
import { JOB_PRIORITY } from '@app/queue';
import { MailService, maskEmailForDisplay } from '../mail.service';
import type { EmailQueue } from '../queue/email.queue';
import type { EmailLogRepository } from '../repository/email-log.repository';
import { EmailType } from '../types/email-type.enum';

describe('MailService', () => {
  let queue: jest.Mocked<Pick<EmailQueue, 'enqueue'>>;
  let emailLogs: jest.Mocked<Pick<EmailLogRepository, 'create'>>;
  let service: MailService;

  const configService = {
    mail: { provider: 'resend' },
  } as unknown as AppConfigService;

  beforeEach(() => {
    queue = { enqueue: jest.fn().mockResolvedValue('job-1') };
    emailLogs = { create: jest.fn().mockResolvedValue('log-1') };
    service = new MailService(
      queue as unknown as EmailQueue,
      emailLogs as unknown as EmailLogRepository,
      configService,
    );
  });

  it('enqueues rather than sending — no provider is touched', async () => {
    await service.sendWelcome('asha@example.com', { firstName: 'Asha' });

    expect(queue.enqueue).toHaveBeenCalledTimes(1);
    const [data] = queue.enqueue.mock.calls[0];
    expect(data.emailType).toBe(EmailType.WELCOME);
    expect(data.to).toBe('asha@example.com');
  });

  it('writes a QUEUED EmailLog before enqueuing and passes its id to the job', async () => {
    const id = await service.sendOtp('asha@example.com', { code: '482910' });

    expect(id).toBe('log-1');
    expect(emailLogs.create).toHaveBeenCalledWith(
      expect.objectContaining({
        recipient: 'asha@example.com',
        template: 'otp',
      }),
    );
    // The id must ride along, otherwise each retry writes a new row.
    expect(queue.enqueue.mock.calls[0][0].emailLogId).toBe('log-1');
  });

  it('renders the subject at enqueue time so the log row is readable', async () => {
    await service.sendOtp('asha@example.com', { code: '482910' });
    expect(emailLogs.create).toHaveBeenCalledWith(
      expect.objectContaining({
        subject: '482910 is your Nenjam Matrimony verification code',
      }),
    );
  });

  it('rejects an invalid recipient at the call site instead of queueing a doomed job', async () => {
    await expect(
      service.sendWelcome('not-an-email', { firstName: 'Asha' }),
    ).rejects.toThrow(/valid email address/);

    expect(queue.enqueue).not.toHaveBeenCalled();
    expect(emailLogs.create).not.toHaveBeenCalled();
  });

  it('marks transactional mail so the layout suppresses the unsubscribe link', async () => {
    await service.sendOtp('asha@example.com', { code: '1' });
    expect(queue.enqueue.mock.calls[0][0].payload.transactional).toBe(true);

    queue.enqueue.mockClear();
    await service.sendWeeklyDigest('asha@example.com', {
      firstName: 'Asha',
      matchCount: 0,
      matches: [],
    });
    expect(queue.enqueue.mock.calls[0][0].payload.transactional).toBe(false);
  });

  it('masks the address rendered into password-reset copy', async () => {
    await service.sendForgotPassword('asha@example.com', {
      resetUrl: 'https://x.test/r',
    });
    expect(queue.enqueue.mock.calls[0][0].payload.maskedEmail).toBe(
      'as**@example.com',
    );
  });

  it('truncates a long message preview before it reaches the job payload', async () => {
    await service.sendNewMessage('asha@example.com', {
      senderName: 'Vikram',
      messagePreview: 'x'.repeat(500),
      conversationUrl: 'https://x.test/c',
    });
    const preview = queue.enqueue.mock.calls[0][0].payload
      .messagePreview as string;
    expect(preview.length).toBeLessThanOrEqual(180);
    expect(preview.endsWith('…')).toBe(true);
  });

  it('forwards dedupe and delay options to the queue', async () => {
    await service.sendWeeklyDigest(
      'asha@example.com',
      { firstName: 'Asha', matchCount: 1, matches: [] },
      { dedupeKey: 'digest:u1:2026-W31', delayMs: 5000 },
    );
    expect(queue.enqueue.mock.calls[0][1]).toEqual({
      dedupeKey: 'digest:u1:2026-W31',
      delayMs: 5000,
    });
  });

  it('still enqueues when the EmailLog write fails — logging must not block delivery', async () => {
    emailLogs.create.mockResolvedValue(undefined);

    await expect(
      service.sendWelcome('asha@example.com', { firstName: 'Asha' }),
    ).resolves.toBeUndefined();
    expect(queue.enqueue).toHaveBeenCalledTimes(1);
  });
});

describe('priority assignment', () => {
  it('ranks an OTP above a weekly digest', () => {
    // BullMQ runs LOWER numbers first — a backlog of digests must never sit
    // in front of someone waiting on a login code.
    expect(JOB_PRIORITY.CRITICAL).toBeLessThan(JOB_PRIORITY.LOW);
  });
});

describe('maskEmailForDisplay', () => {
  it.each([
    ['asha@example.com', 'as**@example.com'],
    ['ab@x.io', 'ab*@x.io'],
    ['not-an-email', '***'],
  ])('masks %s', (input, expected) => {
    expect(maskEmailForDisplay(input)).toBe(expected);
  });
});
