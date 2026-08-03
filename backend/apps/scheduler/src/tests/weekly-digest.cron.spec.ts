import type { PrismaService } from '@app/database';
import type { MailService } from '@app/mail';
import { WeeklyDigestCron, isoWeekKey } from '../cron/weekly-digest.cron';

function user(over: Record<string, unknown> = {}) {
  return {
    id: 'u1',
    email: 'asha@example.com',
    profile: { firstName: 'Asha', gender: 'FEMALE' },
    partnerPreference: { minAge: 28, maxAge: 38 },
    ...over,
  };
}

function candidate(over: Record<string, unknown> = {}) {
  return {
    userId: 'c1',
    firstName: 'Vikram',
    dob: new Date('1993-05-02'),
    currentCity: 'Chennai',
    ...over,
  };
}

/** Shapes of the Prisma args / MailService params these tests assert on.
 *  Declared so `mock.calls[...]` is typed rather than `any`. */
type ProfileFindManyArgs = {
  where: {
    gender: string;
    dob: { gte: Date; lte: Date };
    user: {
      blocksMade: { none: { blockedUserId: string } };
      blocksReceived: { none: { blockerId: string } };
    };
  };
};
type DigestParams = {
  matchCount: number;
  matches: { name: string; city: string }[];
};
type DigestOptions = { dedupeKey: string };

describe('WeeklyDigestCron', () => {
  let findManyUsers: jest.Mock;
  let findManyProfiles: jest.Mock<Promise<unknown>, [ProfileFindManyArgs]>;
  let mail: {
    sendWeeklyDigest: jest.Mock<
      Promise<string>,
      [string, DigestParams, DigestOptions]
    >;
  };
  let cron: WeeklyDigestCron;

  beforeEach(() => {
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    findManyUsers = jest.fn().mockResolvedValue([user()]);
    findManyProfiles = jest
      .fn<Promise<unknown>, [ProfileFindManyArgs]>()
      .mockResolvedValue([candidate()]);
    mail = {
      sendWeeklyDigest: jest
        .fn<Promise<string>, [string, DigestParams, DigestOptions]>()
        .mockResolvedValue('log-1'),
    };

    cron = new WeeklyDigestCron(
      {
        user: { findMany: findManyUsers },
        userProfile: { findMany: findManyProfiles },
      } as unknown as PrismaService,
      mail as unknown as MailService,
    );
  });

  afterEach(() => jest.restoreAllMocks());

  it('queues a digest for a member with new candidates', async () => {
    await cron.run();

    expect(mail.sendWeeklyDigest).toHaveBeenCalledTimes(1);
    const [to, params] = mail.sendWeeklyDigest.mock.calls[0];
    expect(to).toBe('asha@example.com');
    expect(params.matchCount).toBe(1);
    expect(params.matches[0]).toMatchObject({
      name: 'Vikram',
      city: 'Chennai',
    });
  });

  it('sends nothing to a member with no new candidates', async () => {
    // An empty digest is worse than no digest.
    findManyProfiles.mockResolvedValue([]);

    await cron.run();
    expect(mail.sendWeeklyDigest).not.toHaveBeenCalled();
  });

  it('uses a per-week dedupe key so a re-run cannot double-send', async () => {
    await cron.run();

    const options = mail.sendWeeklyDigest.mock.calls[0][2];
    expect(options.dedupeKey).toBe(`digest:u1:${isoWeekKey(new Date())}`);
  });

  it('searches for the opposite gender', async () => {
    await cron.run();
    expect(findManyProfiles.mock.calls[0][0].where.gender).toBe('MALE');

    findManyProfiles.mockClear();
    findManyUsers.mockResolvedValue([
      user({ profile: { firstName: 'Vikram', gender: 'MALE' } }),
    ]);
    await cron.run();
    expect(findManyProfiles.mock.calls[0][0].where.gender).toBe('FEMALE');
  });

  it('translates the age range into an inverted DOB range', async () => {
    await cron.run();

    const { gte, lte } = findManyProfiles.mock.calls[0][0].where.dob;
    // Oldest acceptable partner (38) => EARLIEST birth date.
    expect(gte.getTime()).toBeLessThan(lte.getTime());
    const spanYears = lte.getFullYear() - gte.getFullYear();
    expect(spanYears).toBe(11); // 38 - 28 + 1
  });

  it('excludes blocked members in both directions', async () => {
    await cron.run();

    const where = findManyProfiles.mock.calls[0][0].where.user;
    expect(where.blocksMade).toEqual({ none: { blockedUserId: 'u1' } });
    expect(where.blocksReceived).toEqual({ none: { blockerId: 'u1' } });
  });

  it('skips members with no email or no finalized profile', async () => {
    findManyUsers.mockResolvedValue([
      user({ email: null }),
      user({ id: 'u2', profile: null }),
    ]);

    await cron.run();
    expect(mail.sendWeeklyDigest).not.toHaveBeenCalled();
  });

  it('never throws — a cron that throws silently stops all future ticks', async () => {
    findManyUsers.mockRejectedValue(new Error('neon unreachable'));

    await expect(cron.run()).resolves.toBeUndefined();
  });

  it('keeps already-queued digests when a later page fails', async () => {
    findManyUsers
      .mockResolvedValueOnce(
        Array.from({ length: 200 }, (_, i) => user({ id: `u${i}` })),
      )
      .mockRejectedValueOnce(new Error('neon unreachable'));

    await expect(cron.run()).resolves.toBeUndefined();
    // The first full page still went out; the dedupe key makes a re-run safe.
    expect(mail.sendWeeklyDigest).toHaveBeenCalledTimes(200);
  });
});

describe('isoWeekKey', () => {
  it('is stable across a single week', () => {
    // Mon 27 Jul 2026 .. Sun 2 Aug 2026 are the same ISO week.
    expect(isoWeekKey(new Date('2026-07-27T00:00:00Z'))).toBe(
      isoWeekKey(new Date('2026-08-02T00:00:00Z')),
    );
  });

  it('changes at the week boundary', () => {
    expect(isoWeekKey(new Date('2026-08-02T00:00:00Z'))).not.toBe(
      isoWeekKey(new Date('2026-08-03T00:00:00Z')),
    );
  });

  it('formats as YYYY-Www', () => {
    expect(isoWeekKey(new Date('2026-08-03T00:00:00Z'))).toMatch(
      /^\d{4}-W\d{2}$/,
    );
  });
});
