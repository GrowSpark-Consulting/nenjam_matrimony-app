import { AgentConfigError } from '../config/agent-config.service';
import {
  REFERRAL_DISCOUNT_ONLY_IN_CREDIT_WINDOW_KEY,
  REFERRAL_MEMBER_DISCOUNT_BPS_KEY,
} from '../settings/agent-program-settings';
import {
  AgentHarness,
  expectServiceError,
  IP_LIMIT,
  makeAgentHarness,
  PHONE,
  START,
} from '../testing/agent-test-harness';

const CODE = 'NM7K2P9X';
const OTHER_CODE = 'NM3H4J5K';
const LIST = 99_900;
const DAY = 86_400_000;

const quoteFor = (
  h: AgentHarness,
  o: { promoCode?: string | null; listAmountPaise?: number } = {},
) =>
  h.referralQuote.quote({
    memberId: 'member-1',
    promoCode: o.promoCode,
    planPriceId: 'price-1',
    listAmountPaise: o.listAmountPaise ?? LIST,
  });

describe('AgentReferralQuoteService', () => {
  let h: AgentHarness;
  beforeEach(() => {
    h = makeAgentHarness({
      [REFERRAL_DISCOUNT_ONLY_IN_CREDIT_WINDOW_KEY]: true,
    });
    h.seedMember('member-1');
  });

  const seedAgentWithCode = async (
    status = 'ACTIVE',
    o: { id?: string; phone?: string; code?: string; name?: string } = {},
  ) => {
    const id = o.id ?? 'agent-1';
    await h.seedAgent(status, {
      id,
      phoneE164: o.phone ?? PHONE,
      name: o.name ?? 'Ravi Kumar',
    });
    await h.codes.create({
      id: `code-of-${id}`,
      agentId: id,
      code: o.code ?? CODE,
      isPrimary: true,
      isActive: true,
      createdAt: START,
    });
  };

  const seedAttribution = (
    o: {
      agentId?: string;
      status?: 'ACTIVE' | 'CONVERTED' | 'EXPIRED' | 'REJECTED';
      windowEndsAt?: Date;
    } = {},
  ) =>
    h.attributions.create({
      id: 'attr-1',
      memberId: 'member-1',
      agentId: o.agentId ?? 'agent-1',
      codeId: 'code-of-agent-1',
      source: 'CODE_AT_SIGNUP',
      memberPhoneHash: 'hash-of-member-1',
      attributedAt: START,
      status: o.status ?? 'ACTIVE',
      windowEndsAt: o.windowEndsAt ?? new Date(START.getTime() + 60 * DAY),
      needsReview: false,
    });

  const attemptsRecorded = async () =>
    (await h.attempts.window('REQUESTER', 'quote:member-1', new Date(0))).count;

  describe('a typed code', () => {
    it('gives the first-plan discount and names the code to hold', async () => {
      await seedAgentWithCode();
      await expect(quoteFor(h, { promoCode: CODE })).resolves.toEqual({
        discountBps: 500,
        discountPaise: 4_995,
        discountSource: 'REFERRAL_FIRST_PLAN',
        amountPaidPaise: 94_905,
        heldReferralCodeId: 'code-of-agent-1',
        agentDisplayName: 'Ravi K.',
      });
    });

    it('normalises what was typed', async () => {
      await seedAgentWithCode();
      const quote = await quoteFor(h, { promoCode: '  nm7k-2p9x ' });
      expect(quote.discountSource).toBe('REFERRAL_FIRST_PLAN');
    });

    it('no code at all: no discount, no reason, nothing counted', async () => {
      await seedAgentWithCode();
      await expect(quoteFor(h)).resolves.toEqual({
        discountBps: 0,
        discountPaise: 0,
        discountSource: 'NONE',
        amountPaidPaise: LIST,
      });
      await expect(quoteFor(h, { promoCode: '   ' })).resolves.toMatchObject({
        discountSource: 'NONE',
      });
      expect(await attemptsRecorded()).toBe(0);
    });

    it('uses the setting, not a constant', async () => {
      await seedAgentWithCode();
      h.settings.set(REFERRAL_MEMBER_DISCOUNT_BPS_KEY, 1_000);
      await expect(
        quoteFor(h, { promoCode: CODE, listAmountPaise: 50_000 }),
      ).resolves.toMatchObject({ discountBps: 1_000, discountPaise: 5_000 });
      h.settings.set(REFERRAL_MEMBER_DISCOUNT_BPS_KEY, 0);
      await expect(quoteFor(h, { promoCode: CODE })).resolves.toMatchObject({
        discountBps: 0,
        discountSource: 'NONE',
        amountPaidPaise: LIST,
      });
    });
  });

  describe('first paid plan only', () => {
    it('a member who has paid gets no discount, with a valid code', async () => {
      await seedAgentWithCode();
      h.seedMember('member-1', { hasPaid: true });
      await expect(quoteFor(h, { promoCode: CODE })).resolves.toEqual({
        discountBps: 0,
        discountPaise: 0,
        discountSource: 'NONE',
        amountPaidPaise: LIST,
        rejectedReason: 'NOT_FIRST_PLAN',
      });
      expect(await attemptsRecorded()).toBe(0);
    });

    it('a member who has paid gets no discount through their attribution either', async () => {
      await seedAgentWithCode();
      await seedAttribution();
      h.seedMember('member-1', { hasPaid: true });
      await expect(quoteFor(h)).resolves.toMatchObject({
        discountSource: 'NONE',
        rejectedReason: 'NOT_FIRST_PLAN',
      });
    });
  });

  describe('a member already credited to an agent: the first agent stays', () => {
    it('uses the attribution, no code needed', async () => {
      await seedAgentWithCode();
      await seedAttribution();
      await expect(quoteFor(h)).resolves.toEqual({
        discountBps: 500,
        discountPaise: 4_995,
        discountSource: 'REFERRAL_FIRST_PLAN',
        amountPaidPaise: 94_905,
        agentDisplayName: 'Ravi K.',
      });
    });

    it('a typed code of another agent is ignored: the first agent is used', async () => {
      await seedAgentWithCode();
      await seedAgentWithCode('ACTIVE', {
        id: 'agent-2',
        phone: '+919000000001',
        code: OTHER_CODE,
        name: 'Meena Sundar',
      });
      await seedAttribution({ agentId: 'agent-1' });
      const quote = await quoteFor(h, { promoCode: OTHER_CODE });
      expect(quote).toEqual({
        discountBps: 500,
        discountPaise: 4_995,
        discountSource: 'REFERRAL_FIRST_PLAN',
        amountPaidPaise: 94_905,
        agentDisplayName: 'Ravi K.',
        rejectedReason: 'ALREADY_ATTRIBUTED',
      });
      expect(quote.heldReferralCodeId).toBeUndefined();
      const stored = await h.attributions.findByMemberId('member-1');
      expect(stored?.agentId).toBe('agent-1');
      expect(await attemptsRecorded()).toBe(0);
    });

    it('needs the attribution to be ACTIVE', async () => {
      await seedAgentWithCode();
      await seedAttribution({ status: 'EXPIRED' });
      await expect(quoteFor(h)).resolves.toMatchObject({
        discountSource: 'NONE',
      });
    });

    it('a rejected attribution gives nothing, and a typed code does not replace it', async () => {
      await seedAgentWithCode();
      await seedAttribution({ status: 'REJECTED' });
      await expect(quoteFor(h, { promoCode: CODE })).resolves.toMatchObject({
        discountSource: 'NONE',
        rejectedReason: 'INVALID',
      });
    });

    it('stops at the end of the credit window when the setting says so', async () => {
      await seedAgentWithCode();
      await seedAttribution({
        windowEndsAt: new Date(START.getTime() + DAY),
      });
      h.clock.advance(2 * DAY);
      await expect(quoteFor(h)).resolves.toMatchObject({
        discountPaise: 0,
        discountSource: 'NONE',
        amountPaidPaise: LIST,
      });
    });

    it('keeps the discount after the window when the setting says it is not limited', async () => {
      await seedAgentWithCode();
      await seedAttribution({
        windowEndsAt: new Date(START.getTime() + DAY),
      });
      h.clock.advance(2 * DAY);
      h.settings.set(REFERRAL_DISCOUNT_ONLY_IN_CREDIT_WINDOW_KEY, false);
      await expect(quoteFor(h)).resolves.toMatchObject({
        discountPaise: 4_995,
        discountSource: 'REFERRAL_FIRST_PLAN',
      });
    });
  });

  describe('a paused agent gives no discount', () => {
    it('a typed code of a paused agent', async () => {
      await seedAgentWithCode('SUSPENDED');
      await expect(quoteFor(h, { promoCode: CODE })).resolves.toEqual({
        discountBps: 0,
        discountPaise: 0,
        discountSource: 'NONE',
        amountPaidPaise: LIST,
        rejectedReason: 'AGENT_PAUSED',
      });
    });

    it('the existing agent was paused after crediting the member', async () => {
      await seedAgentWithCode('SUSPENDED');
      await seedAttribution();
      await expect(quoteFor(h)).resolves.toMatchObject({
        discountSource: 'NONE',
        rejectedReason: 'AGENT_PAUSED',
      });
    });

    it('a terminated agent is simply not a valid code', async () => {
      await seedAgentWithCode('TERMINATED');
      await expect(quoteFor(h, { promoCode: CODE })).resolves.toMatchObject({
        discountSource: 'NONE',
        rejectedReason: 'INVALID',
      });
    });
  });

  describe('a member cannot use their own code', () => {
    it("the code belongs to the member's own phone", async () => {
      await seedAgentWithCode();
      h.seedMember('member-1', { phoneHash: h.hasher.hash('PHONE', PHONE) });
      await expect(quoteFor(h, { promoCode: CODE })).resolves.toEqual({
        discountBps: 0,
        discountPaise: 0,
        discountSource: 'NONE',
        amountPaidPaise: LIST,
        rejectedReason: 'SELF_REFERRAL',
      });
    });

    it('another account on a phone that is already credited is a conflict', async () => {
      await seedAgentWithCode();
      await seedAgentWithCode('ACTIVE', {
        id: 'agent-2',
        phone: '+919000000001',
        code: OTHER_CODE,
      });
      h.seedMember('member-2', { phoneHash: 'shared-hash' });
      h.seedMember('member-1', { phoneHash: 'shared-hash' });
      await h.attributions.create({
        id: 'attr-2',
        memberId: 'member-2',
        agentId: 'agent-2',
        codeId: 'code-of-agent-2',
        source: 'CODE_AT_SIGNUP',
        memberPhoneHash: 'shared-hash',
        attributedAt: START,
        status: 'ACTIVE',
        windowEndsAt: new Date(START.getTime() + 60 * DAY),
        needsReview: false,
      });
      await expect(quoteFor(h, { promoCode: CODE })).resolves.toMatchObject({
        discountSource: 'NONE',
        rejectedReason: 'ALREADY_ATTRIBUTED',
      });
    });
  });

  describe('a member with no verified phone', () => {
    beforeEach(() => h.seedMember('member-1', { phoneHash: null }));

    it('gets no discount: PHONE_NOT_VERIFIED, and payment goes on', async () => {
      await seedAgentWithCode();
      const create = jest.spyOn(h.attributions, 'create');
      await expect(quoteFor(h, { promoCode: CODE })).resolves.toEqual({
        discountBps: 0,
        discountPaise: 0,
        discountSource: 'NONE',
        amountPaidPaise: LIST,
        rejectedReason: 'PHONE_NOT_VERIFIED',
      });
      expect(create).not.toHaveBeenCalled();
    });

    it('with no code there is nothing to report', async () => {
      await seedAgentWithCode();
      await expect(quoteFor(h)).resolves.toEqual({
        discountBps: 0,
        discountPaise: 0,
        discountSource: 'NONE',
        amountPaidPaise: LIST,
      });
    });

    it('a bad code is still reported as INVALID first', async () => {
      await seedAgentWithCode();
      await expect(
        quoteFor(h, { promoCode: 'NM2222XX' }),
      ).resolves.toMatchObject({ rejectedReason: 'INVALID' });
    });
  });

  describe('an invalid code never blocks payment', () => {
    it.each([
      ['an unknown code', 'NM2222XX'],
      ['text that is not a code', 'hello'],
    ])('%s: full price, reason INVALID, no error', async (_name, typed) => {
      await seedAgentWithCode();
      await expect(quoteFor(h, { promoCode: typed })).resolves.toEqual({
        discountBps: 0,
        discountPaise: 0,
        discountSource: 'NONE',
        amountPaidPaise: LIST,
        rejectedReason: 'INVALID',
      });
    });

    it('an inactive code', async () => {
      await seedAgentWithCode();
      await h.codes.create({
        id: 'code-off',
        agentId: 'agent-1',
        code: OTHER_CODE,
        isPrimary: false,
        isActive: false,
        createdAt: START,
      });
      await expect(
        quoteFor(h, { promoCode: OTHER_CODE }),
      ).resolves.toMatchObject({
        amountPaidPaise: LIST,
        rejectedReason: 'INVALID',
      });
    });

    it('too many attempts: still a quote, with no discount', async () => {
      await seedAgentWithCode();
      for (let i = 0; i < IP_LIMIT; i += 1) {
        await quoteFor(h, { promoCode: `NM22222${i + 2}` });
      }
      // Even a good code cannot be used once the limit is hit; payment goes on.
      await expect(quoteFor(h, { promoCode: CODE })).resolves.toEqual({
        discountBps: 0,
        discountPaise: 0,
        discountSource: 'NONE',
        amountPaidPaise: LIST,
        rejectedReason: 'INVALID',
      });
    });
  });

  describe('read-only', () => {
    it('writes nothing but the attempt counter', async () => {
      await seedAgentWithCode();
      await seedAgentWithCode('SUSPENDED', {
        id: 'agent-3',
        phone: '+919000000002',
        code: OTHER_CODE,
      });
      const writes = [
        jest.spyOn(h.attributions, 'create'),
        jest.spyOn(h.codes, 'create'),
        jest.spyOn(h.agents, 'create'),
        jest.spyOn(h.agents, 'update'),
        jest.spyOn(h.audit, 'record'),
        jest.spyOn(h.uow, 'run'),
      ];

      await quoteFor(h, { promoCode: CODE }); // a discount
      await quoteFor(h, { promoCode: OTHER_CODE }); // a paused agent
      await quoteFor(h, { promoCode: 'garbage' }); // invalid
      await quoteFor(h); // no code
      h.seedMember('member-1', { hasPaid: true });
      await quoteFor(h, { promoCode: CODE }); // not the first plan

      for (const spy of writes) expect(spy).not.toHaveBeenCalled();
      expect(await h.attributions.findByMemberId('member-1')).toBeNull();
    });

    it('does not change an existing attribution', async () => {
      await seedAgentWithCode();
      await seedAttribution();
      const before = await h.attributions.findByMemberId('member-1');
      const create = jest.spyOn(h.attributions, 'create');
      await quoteFor(h, { promoCode: OTHER_CODE });
      await quoteFor(h);
      expect(create).not.toHaveBeenCalled();
      expect(await h.attributions.findByMemberId('member-1')).toEqual(before);
    });
  });

  describe('inputs and settings', () => {
    it('an unknown member is UNAUTHORIZED', async () => {
      await expectServiceError(
        h.referralQuote.quote({
          memberId: 'nobody',
          planPriceId: 'price-1',
          listAmountPaise: LIST,
        }),
        'UNAUTHORIZED',
      );
    });

    it.each([-1, 1.5, Number.NaN, Number.MAX_SAFE_INTEGER + 1])(
      'refuses the amount %p',
      async (amount) => {
        await expect(
          quoteFor(h, { listAmountPaise: amount }),
        ).rejects.toBeInstanceOf(RangeError);
      },
    );

    it('refuses an empty plan price id', async () => {
      await expect(
        h.referralQuote.quote({
          memberId: 'member-1',
          planPriceId: '',
          listAmountPaise: LIST,
        }),
      ).rejects.toBeInstanceOf(RangeError);
    });

    it('a free plan stays free', async () => {
      await seedAgentWithCode();
      await expect(
        quoteFor(h, { promoCode: CODE, listAmountPaise: 0 }),
      ).resolves.toMatchObject({ discountPaise: 0, amountPaidPaise: 0 });
    });

    it('a missing discount setting is a config error only when a discount is possible', async () => {
      await seedAgentWithCode();
      h.settings.remove(REFERRAL_MEMBER_DISCOUNT_BPS_KEY);
      await expect(quoteFor(h)).resolves.toMatchObject({
        discountSource: 'NONE',
      });
      await expect(quoteFor(h, { promoCode: CODE })).rejects.toBeInstanceOf(
        AgentConfigError,
      );
    });
  });
});
