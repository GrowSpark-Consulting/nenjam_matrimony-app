import { AgentConfigError } from '../config/agent-config.service';
import { REFERRAL_MEMBER_DISCOUNT_BPS_KEY } from '../settings/agent-program-settings';
import {
  AgentHarness,
  expectServiceError,
  makeAgentHarness,
  START,
} from '../testing/agent-test-harness';
import { AgentReferralService } from './agent-referral.service';

const DAY = 86_400_000;

describe('AgentReferralService', () => {
  let h: AgentHarness;
  beforeEach(() => {
    h = makeAgentHarness();
  });

  const asAgent = async (status = 'ACTIVE', overrides = {}) => {
    await h.seedAgent(status, overrides);
    return h.claimsOf(await h.signInAs());
  };

  const addCode = (
    id: string,
    code: string,
    o: {
      agentId?: string;
      isPrimary?: boolean;
      isActive?: boolean;
      at?: Date;
    } = {},
  ) =>
    h.codes.create({
      id,
      agentId: o.agentId ?? 'agent-1',
      code,
      isPrimary: o.isPrimary ?? false,
      isActive: o.isActive ?? true,
      createdAt: o.at ?? START,
    });

  describe('getLinks', () => {
    it("lists the agent's active codes, primary first", async () => {
      const claims = await asAgent();
      await addCode('c2', 'NM2222AA', { at: new Date(START.getTime() + 1000) });
      await addCode('c1', 'NM7K2P9X', {
        isPrimary: true,
        at: new Date(START.getTime() + 5000),
      });
      const { items } = await h.referrals.getLinks(claims);
      expect(items.map((i) => i.code)).toEqual(['NM7K2P9X', 'NM2222AA']);
      expect(items[0]).toMatchObject({
        codeId: 'c1',
        isPrimary: true,
        shareable: true,
      });
    });

    it("leaves out inactive codes and other agents' codes", async () => {
      const claims = await asAgent();
      await addCode('c1', 'NM7K2P9X', { isPrimary: true });
      await addCode('c2', 'NM2222AA', { isActive: false });
      await addCode('c3', 'NM3333BB', {
        agentId: 'someone-else',
        isPrimary: true,
      });
      const { items } = await h.referrals.getLinks(claims);
      expect(items.map((i) => i.code)).toEqual(['NM7K2P9X']);
    });

    it('with no link yet: link and qrPayload are null and the message has no link line', async () => {
      const claims = await asAgent();
      await addCode('c1', 'NM7K2P9X', { isPrimary: true });
      const [item] = (await h.referrals.getLinks(claims)).items;
      expect(item.link).toBeNull();
      expect(item.qrPayload).toBeNull();
      expect(item.shareMessages).toHaveLength(1);
      expect(item.shareMessages[0].text.en).toBe(
        "Hi! I'm Ravi Kumar. Join Nenjam, a trusted matrimony app, and use my referral code NM7K2P9X when you sign up to get 5% off your first plan.",
      );
      expect(item.shareMessages[0].text.ta).toContain('Ravi Kumar');
      expect(item.shareMessages[0].text.ta).toContain('NM7K2P9X');
      expect(item.shareMessages[0].text.ta).toContain('5% தள்ளுபடி');
      expect(item.shareMessages[0].text.en).not.toContain('\n');
      expect(item.shareMessages[0].text.ta).not.toContain('{');
    });

    it('with a link: qrPayload equals the link and the message ends with it on its own line', async () => {
      const claims = await asAgent();
      await addCode('c1', 'NM7K2P9X', { isPrimary: true });
      const service = new AgentReferralService({
        access: h.me,
        codes: h.codes,
        attributions: h.attributions,
        members: h.members,
        content: h.content,
        settings: h.settings,
        linkFor: (code) => `https://portal.example.invalid/r/${code}`,
      });
      const [item] = (await service.getLinks(claims)).items;
      expect(item.link).toBe('https://portal.example.invalid/r/NM7K2P9X');
      expect(item.qrPayload).toBe(item.link);
      expect(
        item.shareMessages[0].text.en.endsWith(
          '\nhttps://portal.example.invalid/r/NM7K2P9X',
        ),
      ).toBe(true);
    });

    it('takes the discount from the settings on every call', async () => {
      const claims = await asAgent();
      await addCode('c1', 'NM7K2P9X', { isPrimary: true });
      h.settings.set(REFERRAL_MEMBER_DISCOUNT_BPS_KEY, 1000);
      const [item] = (await h.referrals.getLinks(claims)).items;
      expect(item.shareMessages[0].text.en).toContain('get 10% off');
    });

    it('fails clearly when the discount setting is missing', async () => {
      const claims = await asAgent();
      h.settings.remove(REFERRAL_MEMBER_DISCOUNT_BPS_KEY);
      await expect(h.referrals.getLinks(claims)).rejects.toBeInstanceOf(
        AgentConfigError,
      );
    });

    it('a paused agent gets the list with shareable false', async () => {
      const claims = await asAgent('SUSPENDED');
      await addCode('c1', 'NM7K2P9X', { isPrimary: true });
      const { items } = await h.referrals.getLinks(claims);
      expect(items).toHaveLength(1);
      expect(items[0].shareable).toBe(false);
    });

    it.each(['PENDING_APPROVAL', 'REJECTED', 'TERMINATED'])(
      'a %s agent is refused with AGENT_NOT_ACTIVE and the status',
      async (status) => {
        const claims = await asAgent(status);
        await expectServiceError(
          h.referrals.getLinks(claims),
          'AGENT_NOT_ACTIVE',
          {
            agentStatus: status,
          },
        );
      },
    );

    it('an agent with no codes gets an empty list', async () => {
      const claims = await asAgent();
      await expect(h.referrals.getLinks(claims)).resolves.toEqual({
        items: [],
      });
    });

    it('an applicant is UNAUTHORIZED', async () => {
      const claims = await h.claimsOf(await h.signInAs());
      await expectServiceError(h.referrals.getLinks(claims), 'UNAUTHORIZED');
    });
  });

  describe('listReferrals', () => {
    const seed = async (count: number, agentId = 'agent-1') => {
      for (let i = 1; i <= count; i++) {
        await h.seedReferral({
          id: `r${String(i).padStart(2, '0')}`,
          agentId,
          at: new Date(START.getTime() + i * DAY),
        });
      }
    };

    it('returns the allow-listed view, newest first, and nothing else', async () => {
      const claims = await asAgent();
      await seed(3);
      const page = await h.referrals.listReferrals(claims);
      expect(page.items.map((i) => i.id)).toEqual(['r03', 'r02', 'r01']);
      expect(page.nextCursor).toBeNull();
      expect(Object.keys(page.items[0]).sort()).toEqual(
        [
          'age',
          'city',
          'commissionStatus',
          'displayName',
          'id',
          'maskedPhone',
          'planName',
          'profileCompletenessPct',
          'purchasedAt',
          'signedUpAt',
          'stage',
        ].sort(),
      );
      expect(page.items[0]).toMatchObject({
        displayName: 'Priya S.',
        maskedPhone: '+91 90***002',
        city: 'Madurai',
        stage: 'REGISTERED',
        commissionStatus: null,
      });
      const json = JSON.stringify(page);
      expect(json).not.toContain('9000000002');
      expect(json).not.toContain('member-');
      expect(json).not.toContain('Sharma');
    });

    it('is empty for an agent with no referrals', async () => {
      const claims = await asAgent();
      await expect(h.referrals.listReferrals(claims)).resolves.toEqual({
        items: [],
        nextCursor: null,
      });
    });

    it('uses a default page of 20 and a nextCursor when there are more', async () => {
      const claims = await asAgent();
      await seed(25);
      const first = await h.referrals.listReferrals(claims);
      expect(first.items).toHaveLength(20);
      expect(first.nextCursor).toEqual(expect.any(String));
      const second = await h.referrals.listReferrals(claims, {
        cursor: first.nextCursor!,
      });
      expect(second.items).toHaveLength(5);
      expect(second.nextCursor).toBeNull();
    });

    it('pages through everything exactly once, in order, with no repeats or gaps', async () => {
      const claims = await asAgent();
      await seed(7);
      const seen: string[] = [];
      let cursor: string | undefined;
      let pages = 0;
      do {
        const page = await h.referrals.listReferrals(claims, {
          limit: 3,
          cursor,
        });
        seen.push(...page.items.map((i) => i.id));
        cursor = page.nextCursor ?? undefined;
        pages += 1;
      } while (cursor !== undefined);
      expect(seen).toEqual(['r07', 'r06', 'r05', 'r04', 'r03', 'r02', 'r01']);
      expect(pages).toBe(3);
    });

    it('nextCursor is null on the last page even when the page is exactly full', async () => {
      const claims = await asAgent();
      await seed(6);
      const first = await h.referrals.listReferrals(claims, { limit: 3 });
      const second = await h.referrals.listReferrals(claims, {
        limit: 3,
        cursor: first.nextCursor!,
      });
      expect(second.items).toHaveLength(3);
      expect(second.nextCursor).toBeNull();
    });

    it('breaks ties between equal times by id, without losing or repeating a row', async () => {
      const claims = await asAgent();
      for (const id of ['ra', 'rb', 'rc', 'rd']) {
        await h.seedReferral({ id, at: START });
      }
      const first = await h.referrals.listReferrals(claims, { limit: 2 });
      const second = await h.referrals.listReferrals(claims, {
        limit: 2,
        cursor: first.nextCursor!,
      });
      expect([...first.items, ...second.items].map((i) => i.id).sort()).toEqual(
        ['ra', 'rb', 'rc', 'rd'],
      );
    });

    it('the cursor is opaque text', async () => {
      const claims = await asAgent();
      await seed(3);
      const { nextCursor } = await h.referrals.listReferrals(claims, {
        limit: 1,
      });
      expect(nextCursor).toMatch(/^[A-Za-z0-9_-]+$/);
      expect(nextCursor).not.toContain('r02');
    });

    it('accepts the limit boundaries 1 and 50', async () => {
      const claims = await asAgent();
      await seed(2);
      await expect(
        h.referrals.listReferrals(claims, { limit: 1 }),
      ).resolves.toMatchObject({
        items: [{ id: 'r02' }],
      });
      await expect(
        h.referrals.listReferrals(claims, { limit: 50 }),
      ).resolves.toBeDefined();
    });

    it.each([0, -1, 51, 1.5, NaN])('refuses the limit %p', async (limit) => {
      const claims = await asAgent();
      await expectServiceError(
        h.referrals.listReferrals(claims, { limit }),
        'VALIDATION_FAILED',
        { fields: ['limit'] },
      );
    });

    it.each([
      '',
      'not-a-cursor',
      'e30',
      Buffer.from('{"t":"x","i":"y"}').toString('base64url'),
      Buffer.from('{"t":"2026-10-28T10:00:00.000Z"}').toString('base64url'),
      'x'.repeat(201),
    ])('refuses the cursor %p', async (cursor) => {
      const claims = await asAgent();
      await expectServiceError(
        h.referrals.listReferrals(claims, { cursor }),
        'VALIDATION_FAILED',
        { fields: ['cursor'] },
      );
    });

    it('refuses an unknown stage and names every bad field', async () => {
      const claims = await asAgent();
      await expectServiceError(
        h.referrals.listReferrals(claims, { stage: 'WON', limit: 0 }),
        'VALIDATION_FAILED',
        { fields: ['limit', 'stage'] },
      );
    });

    it('filters by stage and still pages correctly through the matches', async () => {
      const claims = await asAgent();
      for (let i = 1; i <= 9; i++) {
        await h.seedReferral({
          id: `r${i}`,
          at: new Date(START.getTime() + i * DAY),
          stage: i % 3 === 0 ? 'PURCHASED' : 'REGISTERED',
        });
      }
      const first = await h.referrals.listReferrals(claims, {
        stage: 'PURCHASED',
        limit: 2,
      });
      expect(first.items.map((i) => i.id)).toEqual(['r9', 'r6']);
      expect(first.nextCursor).not.toBeNull();
      const second = await h.referrals.listReferrals(claims, {
        stage: 'PURCHASED',
        limit: 2,
        cursor: first.nextCursor!,
      });
      expect(second.items.map((i) => i.id)).toEqual(['r3']);
      expect(second.nextCursor).toBeNull();
    });

    it('never shows REJECTED attributions', async () => {
      const claims = await asAgent();
      await h.seedReferral({ id: 'ok', at: START });
      await h.seedReferral({
        id: 'bad',
        at: new Date(START.getTime() + DAY),
        status: 'REJECTED',
      });
      const page = await h.referrals.listReferrals(claims);
      expect(page.items.map((i) => i.id)).toEqual(['ok']);
    });

    it('skips a referral whose member has vanished, without breaking the page', async () => {
      const claims = await asAgent();
      await seed(3);
      jest
        .spyOn(h.members, 'getReferralViewFields')
        .mockResolvedValueOnce(null);
      const page = await h.referrals.listReferrals(claims, { limit: 5 });
      expect(page.items.map((i) => i.id)).toEqual(['r02', 'r01']);
    });

    it('skips a referral whose member account was deleted (null member)', async () => {
      const claims = await asAgent();
      await seed(2);
      await h.attributions.create({
        id: 'gone',
        memberId: null,
        agentId: 'agent-1',
        codeId: null,
        source: 'CODE_AT_SIGNUP',
        memberPhoneHash: 'hash-of-gone',
        attributedAt: new Date(START.getTime() + 10 * DAY),
        status: 'ACTIVE',
        windowEndsAt: new Date(START.getTime() + 70 * DAY),
        needsReview: false,
      });
      const page = await h.referrals.listReferrals(claims, { limit: 5 });
      expect(page.items.map((i) => i.id)).toEqual(['r02', 'r01']);
      await expectServiceError(
        h.referrals.getReferral(claims, 'gone'),
        'REFERRAL_NOT_FOUND',
      );
    });

    it('OWN-AGENT SCOPING: an agent sees only their own referrals', async () => {
      const claims = await asAgent();
      await h.seedAgent('ACTIVE', {
        id: 'agent-2',
        phoneE164: '+919000000001',
      });
      await seed(2, 'agent-1');
      await h.seedReferral({
        id: 'theirs-1',
        agentId: 'agent-2',
        at: new Date(START.getTime() + 9 * DAY),
      });
      await h.seedReferral({
        id: 'theirs-2',
        agentId: 'agent-2',
        at: new Date(START.getTime() + 10 * DAY),
      });
      const page = await h.referrals.listReferrals(claims, { limit: 50 });
      expect(page.items.map((i) => i.id)).toEqual(['r02', 'r01']);
    });

    it("a forged cursor can only move within the caller's own list", async () => {
      const claims = await asAgent();
      await h.seedAgent('ACTIVE', {
        id: 'agent-2',
        phoneE164: '+919000000001',
      });
      await h.seedReferral({ id: 'mine', at: START });
      await h.seedReferral({
        id: 'theirs',
        agentId: 'agent-2',
        at: new Date(START.getTime() - DAY),
      });
      const forged = Buffer.from(
        JSON.stringify({
          t: new Date(START.getTime() + DAY).toISOString(),
          i: 'theirs',
        }),
      ).toString('base64url');
      const page = await h.referrals.listReferrals(claims, { cursor: forged });
      expect(page.items.map((i) => i.id)).toEqual(['mine']);
    });

    it('a paused agent can still read; a terminated or pending one cannot', async () => {
      await expect(
        h.referrals.listReferrals(await asAgent('SUSPENDED')),
      ).resolves.toBeDefined();
      for (const status of ['PENDING_APPROVAL', 'REJECTED', 'TERMINATED']) {
        const other = makeAgentHarness();
        await other.seedAgent(status);
        const claims = await other.claimsOf(await other.signInAs());
        await expectServiceError(
          other.referrals.listReferrals(claims),
          'AGENT_NOT_ACTIVE',
          {
            agentStatus: status,
          },
        );
      }
    });
  });

  describe('getReferral', () => {
    it("returns one of the agent's own referrals", async () => {
      const claims = await asAgent();
      await h.seedReferral({ id: 'r1' });
      await expect(
        h.referrals.getReferral(claims, 'r1'),
      ).resolves.toMatchObject({
        id: 'r1',
        displayName: 'Priya S.',
      });
    });

    it("OWN-AGENT SCOPING: another agent's referral is REFERRAL_NOT_FOUND, same as a missing one", async () => {
      const claims = await asAgent();
      await h.seedAgent('ACTIVE', {
        id: 'agent-2',
        phoneE164: '+919000000001',
      });
      await h.seedReferral({ id: 'theirs', agentId: 'agent-2' });
      const other = await h.referrals
        .getReferral(claims, 'theirs')
        .catch((e: unknown) => e);
      const missing = await h.referrals
        .getReferral(claims, 'no-such-id')
        .catch((e: unknown) => e);
      expect(other).toMatchObject({ code: 'REFERRAL_NOT_FOUND' });
      expect(missing).toMatchObject({ code: 'REFERRAL_NOT_FOUND' });
      expect(JSON.stringify(other)).toBe(JSON.stringify(missing));
    });

    it('a rejected attribution is REFERRAL_NOT_FOUND', async () => {
      const claims = await asAgent();
      await h.seedReferral({ id: 'bad', status: 'REJECTED' });
      await expectServiceError(
        h.referrals.getReferral(claims, 'bad'),
        'REFERRAL_NOT_FOUND',
      );
    });

    it('a vanished member is REFERRAL_NOT_FOUND', async () => {
      const claims = await asAgent();
      await h.seedReferral({ id: 'r1' });
      jest
        .spyOn(h.members, 'getReferralViewFields')
        .mockResolvedValueOnce(null);
      await expectServiceError(
        h.referrals.getReferral(claims, 'r1'),
        'REFERRAL_NOT_FOUND',
      );
    });

    it.each(['', undefined, null, 42])(
      'an id of %p is REFERRAL_NOT_FOUND',
      async (id) => {
        const claims = await asAgent();
        await expectServiceError(
          h.referrals.getReferral(claims, id as unknown as string),
          'REFERRAL_NOT_FOUND',
        );
      },
    );

    it('the status gate applies: a terminated agent is refused', async () => {
      const claims = await asAgent('TERMINATED');
      await expectServiceError(
        h.referrals.getReferral(claims, 'r1'),
        'AGENT_NOT_ACTIVE',
        {
          agentStatus: 'TERMINATED',
        },
      );
    });
  });
});
