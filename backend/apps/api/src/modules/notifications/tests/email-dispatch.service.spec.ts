import type { AppConfigService } from '@app/config';
import type { MailService } from '@app/mail';
import type { PrismaService } from '@app/database';
import {
  EmailDispatchService,
  ageFrom,
} from '../services/email-dispatch.service';

const configService = {
  mail: { appUrl: 'https://app.example.com/' },
} as unknown as AppConfigService;

function recipient(overrides: Record<string, unknown> = {}) {
  return {
    email: 'asha@example.com',
    profile: {
      firstName: 'Asha',
      dob: new Date('1995-04-10'),
      currentCity: 'Chennai',
      profession: 'Architect',
    },
    ...overrides,
  };
}

type UserFindFirstArgs = {
  where: { deletedAt: null; status: { notIn: string[] } };
};

describe('EmailDispatchService', () => {
  let findFirst: jest.Mock<Promise<unknown>, [UserFindFirstArgs]>;
  let mail: {
    sendWelcome: jest.Mock<Promise<string>, [string, Record<string, unknown>]>;
    sendMatchFound: jest.Mock<
      Promise<string>,
      [string, { matchProfileUrl: string }]
    >;
    sendNewMessage: jest.Mock<
      Promise<string>,
      [string, Record<string, unknown>]
    >;
  };
  let service: EmailDispatchService;

  beforeEach(() => {
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    findFirst = jest
      .fn<Promise<unknown>, [UserFindFirstArgs]>()
      .mockResolvedValue(recipient());
    mail = {
      sendWelcome: jest
        .fn<Promise<string>, [string, Record<string, unknown>]>()
        .mockResolvedValue('log-1'),
      sendMatchFound: jest
        .fn<Promise<string>, [string, { matchProfileUrl: string }]>()
        .mockResolvedValue('log-2'),
      sendNewMessage: jest
        .fn<Promise<string>, [string, Record<string, unknown>]>()
        .mockResolvedValue('log-3'),
    };
    service = new EmailDispatchService(
      { user: { findFirst } } as unknown as PrismaService,
      mail as unknown as MailService,
      configService,
    );
  });

  afterEach(() => jest.restoreAllMocks());

  it('resolves the recipient address from a user id', async () => {
    await service.sendWelcome('u1');

    expect(mail.sendWelcome).toHaveBeenCalledWith('asha@example.com', {
      firstName: 'Asha',
      userId: 'u1',
    });
  });

  it('excludes deleted, banned and deactivated members in the query itself', async () => {
    await service.sendWelcome('u1');

    const where = findFirst.mock.calls[0][0].where;
    expect(where.deletedAt).toBeNull();
    expect(where.status.notIn).toEqual(
      expect.arrayContaining(['BANNED', 'DEACTIVATED']),
    );
  });

  it('sends nothing when the member is ineligible', async () => {
    findFirst.mockResolvedValue(null);

    await service.sendWelcome('u1');
    expect(mail.sendWelcome).not.toHaveBeenCalled();
  });

  it('sends nothing when the member has no finalized profile', async () => {
    // Every template addresses people by first name — there is nothing to send.
    findFirst.mockResolvedValue({ email: 'a@b.com', profile: null });

    await service.sendWelcome('u1');
    expect(mail.sendWelcome).not.toHaveBeenCalled();
  });

  it('never throws back into the domain write that triggered it', async () => {
    // The caller's transaction has already committed by this point; throwing
    // would fail a request whose real work succeeded.
    mail.sendWelcome.mockRejectedValue(new Error('redis down'));

    await expect(service.sendWelcome('u1')).resolves.toBeUndefined();
  });

  it('builds an absolute match profile URL without a double slash', async () => {
    await service.sendMatchFound('u1', 'u2');

    const params = mail.sendMatchFound.mock.calls[0][1];
    // configService.mail.appUrl has a trailing slash on purpose in this suite.
    expect(params.matchProfileUrl).toBe('https://app.example.com/profile/u2');
  });

  it('skips the match email when either party is ineligible', async () => {
    findFirst.mockResolvedValueOnce(recipient()).mockResolvedValueOnce(null);

    await service.sendMatchFound('u1', 'u2');
    expect(mail.sendMatchFound).not.toHaveBeenCalled();
  });

  it('passes sender name and conversation URL for a new message', async () => {
    findFirst
      .mockResolvedValueOnce(recipient())
      .mockResolvedValueOnce(
        recipient({ profile: { ...recipient().profile, firstName: 'Vikram' } }),
      );

    await service.sendNewMessage('u1', 'u2', 'Hello there', 'room-9');

    expect(mail.sendNewMessage).toHaveBeenCalledWith('asha@example.com', {
      senderName: 'Vikram',
      messagePreview: 'Hello there',
      conversationUrl: 'https://app.example.com/chat/room-9',
      userId: 'u1',
    });
  });
});

describe('ageFrom', () => {
  it('does not count a birthday that has not happened yet this year', () => {
    const today = new Date();
    const almost = new Date(
      today.getFullYear() - 30,
      today.getMonth(),
      today.getDate() + 1,
    );
    // Tomorrow's birthday means they are still 29.
    expect(ageFrom(almost)).toBe(29);
  });

  it('counts a birthday that has already passed', () => {
    const today = new Date();
    const passed = new Date(
      today.getFullYear() - 30,
      today.getMonth(),
      today.getDate() - 1,
    );
    expect(ageFrom(passed)).toBe(30);
  });
});
