import { AgentConfigError } from '../config/agent-config.service';
import { AgentConflictError } from '../ports/agent-data-ports';
import {
  REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY,
  REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY,
  REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY,
  REFERRAL_CREDIT_WINDOW_DAYS_KEY,
} from '../settings/agent-program-settings';
import {
  AgentHarness,
  CODE_LIMIT,
  expectServiceError,
  IP_LIMIT,
  makeAgentHarness,
  PHONE,
  START,
  VALIDATION_WINDOW,
} from '../testing/agent-test-harness';

const CODE = 'NM7K2P9X';
const INVALID = { valid: false, agentDisplayName: null };

describe('AgentReferralCodeService', () => {
  let h: AgentHarness;
  beforeEach(() => {
    h = makeAgentHarness();
  });

  /** An agent with a primary code, in the given status. */
  const seedAgentWithCode = async (
    status = 'ACTIVE',
    o: {
      id?: string;
      phone?: string;
      code?: string;
      codeActive?: boolean;
    } = {},
  ) => {
    const id = o.id ?? 'agent-1';
    await h.seedAgent(status, { id, phoneE164: o.phone ?? PHONE });
    await h.codes.create({
      id: `code-of-${id}`,
      agentId: id,
      code: o.code ?? CODE,
      isPrimary: true,
      isActive: o.codeActive ?? true,
      createdAt: START,
    });
  };

  describe('validateCode', () => {
    it('an active code of an ACTIVE agent is valid, with first name and last initial', async () => {
      await seedAgentWithCode();
      await expect(
        h.referralCodes.validateCode(CODE, 'hashed-1'),
      ).resolves.toEqual({
        valid: true,
        agentDisplayName: 'Ravi K.',
      });
    });

    it('returns exactly the two documented fields', async () => {
      await seedAgentWithCode();
      const result = await h.referralCodes.validateCode(CODE, 'hashed-1');
      expect(Object.keys(result).sort()).toEqual(['agentDisplayName', 'valid']);
    });

    it.each(['nm7k2p9x', ' NM7K-2P9X ', 'nm 7k2p 9x'])(
      'accepts the way a person types it: %p',
      async (typed) => {
        await seedAgentWithCode();
        await expect(
          h.referralCodes.validateCode(typed, 'hashed-1'),
        ).resolves.toMatchObject({
          valid: true,
        });
      },
    );

    it('every kind of invalid code gives the identical answer', async () => {
      await seedAgentWithCode('ACTIVE', {
        id: 'a-active',
        code: 'NM2222AA',
        codeActive: false,
      });
      await seedAgentWithCode('SUSPENDED', {
        id: 'a-paused',
        phone: '+919000000001',
        code: 'NM3333BB',
      });
      await seedAgentWithCode('PENDING_APPROVAL', {
        id: 'a-pending',
        phone: '+919000000002',
        code: 'NM4444CC',
      });
      await seedAgentWithCode('TERMINATED', {
        id: 'a-ended',
        phone: '+919999999999',
        code: 'NM5555DD',
      });
      const answers: unknown[] = [];
      let n = 0;
      for (const code of [
        'NM9999ZZ', // unknown
        'NM2222AA', // inactive code
        'NM3333BB', // agent paused
        'NM4444CC', // agent pending
        'NM5555DD', // agent terminated
        'NM00000O', // malformed (has 0 and O)
        '',
        'abc',
        'NM7K2P9',
        12345,
        null,
        undefined,
        {},
      ]) {
        answers.push(
          await h.referralCodes.validateCode(code, `hashed-n${++n}`),
        );
      }
      for (const answer of answers) expect(answer).toEqual(INVALID);
      expect(new Set(answers.map((a) => JSON.stringify(a))).size).toBe(1);
    });

    it("shows a single name as is, and the last name's initial for longer names", async () => {
      h.settings.set(REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY, 10);
      await seedAgentWithCode('ACTIVE', { id: 'a1' });
      await h.agents.update('a1', { name: 'Ravi' });
      await expect(
        h.referralCodes.validateCode(CODE, 'hashed-1'),
      ).resolves.toMatchObject({
        agentDisplayName: 'Ravi',
      });
      await h.agents.update('a1', { name: 'Ravi Kumar Singh' });
      await expect(
        h.referralCodes.validateCode(CODE, 'hashed-2'),
      ).resolves.toMatchObject({
        agentDisplayName: 'Ravi S.',
      });
      await h.agents.update('a1', { name: 'ரவி குமார்' });
      await expect(
        h.referralCodes.validateCode(CODE, 'hashed-3'),
      ).resolves.toMatchObject({
        agentDisplayName: 'ரவி கு.',
      });
    });

    it('never reveals anything but the display name (no id, phone, status or code)', async () => {
      await seedAgentWithCode();
      const json = JSON.stringify(
        await h.referralCodes.validateCode(CODE, 'hashed-1'),
      );
      for (const leak of [
        'agent-1',
        '9876543210',
        'ACTIVE',
        CODE,
        'Kumar',
        'Coimbatore',
      ]) {
        expect(json).not.toContain(leak);
      }
    });

    it('writes no attribution and no audit entry', async () => {
      await seedAgentWithCode();
      await h.referralCodes.validateCode(CODE, 'hashed-1');
      expect(h.audit.entries).toHaveLength(0);
      expect(await h.attributions.listByAgent('agent-1')).toHaveLength(0);
    });

    describe('the requester key is opaque (never a raw IP address)', () => {
      it.each([
        '1.2.3.4',
        '203.0.113.7',
        '::1',
        '2401:4900:1c0a:2f3d::1',
        'requester:1.2.3.4',
      ])('refuses the raw address %p and records nothing', async (ip) => {
        await seedAgentWithCode();
        await expect(h.referralCodes.validateCode(CODE, ip)).rejects.toThrow(
          'hashed key, not a raw IP address',
        );
        expect(h.attempts.size).toBe(0);
      });

      it('accepts a hashed key', async () => {
        await seedAgentWithCode();
        await expect(
          h.referralCodes.validateCode(
            CODE,
            'v1:3f5a9c0d2b7e4a118c6d5f0e9a3b7c24',
          ),
        ).resolves.toMatchObject({ valid: true });
      });

      it('refuses an over-long key', async () => {
        await expect(
          h.referralCodes.validateCode(CODE, 'x'.repeat(201)),
        ).rejects.toThrow(RangeError);
      });

      it('stores the key under a namespace, so it can never equal a member key', async () => {
        await h.referralCodes.validateCode(CODE, 'user:m1');
        h.seedMember('m1');
        await seedAgentWithCode();
        await h.referralCodes.attachCode('m1', CODE);
        // two different keys, so neither run counted against the other
        expect(h.attempts.size).toBe(2);
        expect(
          (
            await h.attempts.window(
              'REQUESTER',
              'requester:user:m1',
              new Date(0),
            )
          ).count,
        ).toBe(1);
        expect(
          (await h.attempts.window('REQUESTER', 'user:m1', new Date(0))).count,
        ).toBe(1);
      });
    });

    it('refuses an empty requester', async () => {
      await expect(h.referralCodes.validateCode(CODE, '')).rejects.toThrow(
        RangeError,
      );
    });

    describe('rate limiting', () => {
      it(`the ${IP_LIMIT + 1}th try from one IP in the window is RATE_LIMITED`, async () => {
        await seedAgentWithCode();
        for (let i = 0; i < IP_LIMIT; i++) {
          await h.referralCodes.validateCode(`NM${i}ZZZZZ`, 'hashed-a');
        }
        await expectServiceError(
          h.referralCodes.validateCode(CODE, 'hashed-a'),
          'RATE_LIMITED',
        );
      });

      it('carries retryAfterSeconds: when the oldest attempt leaves the window, rounded up', async () => {
        for (let i = 0; i < IP_LIMIT; i++) {
          await h.referralCodes.validateCode('garbage', 'hashed-a');
          h.clock.advance(1_000);
        }
        // oldest attempt was 3 s ago; window is 60 s
        await expectServiceError(
          h.referralCodes.validateCode('garbage', 'hashed-a'),
          'RATE_LIMITED',
          { retryAfterSeconds: VALIDATION_WINDOW - IP_LIMIT },
        );
      });

      it('is independent per IP', async () => {
        for (let i = 0; i < IP_LIMIT; i++) {
          await h.referralCodes.validateCode('garbage', 'hashed-a');
        }
        await expect(
          h.referralCodes.validateCode('garbage', 'hashed-b'),
        ).resolves.toEqual(INVALID);
      });

      it(`the per-code limit (${CODE_LIMIT}) trips across different IPs`, async () => {
        await seedAgentWithCode();
        for (let i = 0; i < CODE_LIMIT; i++) {
          await h.referralCodes.validateCode(CODE, `hashed-${i}`);
        }
        await expectServiceError(
          h.referralCodes.validateCode(CODE, 'hashed-99'),
          'RATE_LIMITED',
        );
        // a different code is unaffected
        await expect(
          h.referralCodes.validateCode('NM9999ZZ', 'hashed-99'),
        ).resolves.toEqual(INVALID);
      });

      it('blocked attempts do not extend the lockout', async () => {
        await seedAgentWithCode();
        for (let i = 0; i < IP_LIMIT; i++) {
          await h.referralCodes.validateCode('garbage', 'hashed-a');
        }
        const before = h.attempts.size;
        for (let i = 0; i < 5; i++) {
          await expectServiceError(
            h.referralCodes.validateCode('garbage', 'hashed-a'),
            'RATE_LIMITED',
          );
        }
        expect(h.attempts.size).toBe(before);
      });

      it('frees up once the window has passed', async () => {
        for (let i = 0; i < IP_LIMIT; i++) {
          await h.referralCodes.validateCode('garbage', 'hashed-a');
        }
        await expectServiceError(
          h.referralCodes.validateCode('garbage', 'hashed-a'),
          'RATE_LIMITED',
        );
        h.clock.advance(VALIDATION_WINDOW * 1000);
        await expect(
          h.referralCodes.validateCode('garbage', 'hashed-a'),
        ).resolves.toEqual(INVALID);
      });

      it('text that is not a code counts against the IP but never against a code', async () => {
        for (let i = 0; i < CODE_LIMIT + 1; i++) {
          await h.referralCodes.validateCode('garbage', `hashed-${i}`);
        }
        await expect(
          h.referralCodes.validateCode('also garbage', 'hashed-200'),
        ).resolves.toEqual(INVALID);
      });

      it('the limited answer is the same whether or not the code exists', async () => {
        await seedAgentWithCode();
        for (let i = 0; i < IP_LIMIT; i++) {
          await h.referralCodes.validateCode('garbage', 'hashed-a');
        }
        const real = await h.referralCodes
          .validateCode(CODE, 'hashed-a')
          .catch((e: unknown) => e);
        const fake = await h.referralCodes
          .validateCode('NM9999ZZ', 'hashed-a')
          .catch((e: unknown) => e);
        expect(JSON.stringify(real)).toBe(JSON.stringify(fake));
        expect(real).toMatchObject({ code: 'RATE_LIMITED' });
      });

      it('reads the limits from the settings on every call', async () => {
        h.settings.set(REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY, 1);
        await h.referralCodes.validateCode('garbage', 'hashed-a');
        await expectServiceError(
          h.referralCodes.validateCode('garbage', 'hashed-a'),
          'RATE_LIMITED',
        );
        h.settings.set(REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY, 5);
        await expect(
          h.referralCodes.validateCode('garbage', 'hashed-a'),
        ).resolves.toEqual(INVALID);
      });

      it.each([
        REFERRAL_CODE_VALIDATION_IP_LIMIT_KEY,
        REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY,
        REFERRAL_CODE_VALIDATION_WINDOW_SECONDS_KEY,
      ])(
        'fails clearly, and records nothing, when %s is missing',
        async (key) => {
          h.settings.remove(key);
          await expect(
            h.referralCodes.validateCode(CODE, 'hashed-1'),
          ).rejects.toBeInstanceOf(AgentConfigError);
          await expect(
            h.referralCodes.validateCode(CODE, 'hashed-1'),
          ).rejects.toThrow(key);
          expect(h.attempts.size).toBe(0);
        },
      );

      it.each([0, -1, 1.5, '3'])(
        'fails with a RangeError for a limit of %p',
        async (value) => {
          h.settings.set(REFERRAL_CODE_VALIDATION_CODE_LIMIT_KEY, value);
          await expect(
            h.referralCodes.validateCode(CODE, 'hashed-1'),
          ).rejects.toThrow(RangeError);
        },
      );
    });
  });

  describe('attachCode', () => {
    const attach = (
      memberId = 'm1',
      code: unknown = CODE,
      source?: 'CODE_AT_SIGNUP' | 'LINK_OR_QR' | 'ENTERED_AT_PAYMENT',
    ) => h.referralCodes.attachCode(memberId, code, source);

    beforeEach(async () => {
      await seedAgentWithCode();
      h.seedMember('m1');
    });

    it("credits the member to the code's agent and returns the contract fields", async () => {
      const result = await attach();
      expect(result).toEqual({
        attached: true,
        agentDisplayName: 'Ravi K.',
        windowEndsAt: '2026-12-27', // 28 Oct 2026 + 60 days, an Indian date
      });
      expect(Object.keys(result).sort()).toEqual([
        'agentDisplayName',
        'attached',
        'windowEndsAt',
      ]);
    });

    it('stores an ACTIVE attribution with the credit window snapshotted', async () => {
      await attach();
      const stored = await h.attributions.findByMemberId('m1');
      expect(stored).toMatchObject({
        agentId: 'agent-1',
        codeId: 'code-of-agent-1',
        source: 'CODE_AT_SIGNUP',
        status: 'ACTIVE',
        memberPhoneHash: 'hash-of-m1',
        needsReview: false,
      });
      expect(stored!.windowEndsAt.getTime()).toBe(
        START.getTime() + 60 * 86_400_000,
      );
    });

    it('takes the credit window from the settings', async () => {
      h.settings.set(REFERRAL_CREDIT_WINDOW_DAYS_KEY, 30);
      expect((await attach()).windowEndsAt).toBe('2026-11-27');
    });

    it('fails clearly, before writing anything, when the credit window is not set', async () => {
      h.settings.remove(REFERRAL_CREDIT_WINDOW_DAYS_KEY);
      await expect(attach()).rejects.toBeInstanceOf(AgentConfigError);
      expect(await h.attributions.findByMemberId('m1')).toBeNull();
    });

    it('accepts a code the way a person types it', async () => {
      await expect(attach('m1', ' nm7k-2p9x ')).resolves.toMatchObject({
        attached: true,
      });
    });

    it('writes one audit entry in the same transaction, with no personal data', async () => {
      await attach();
      expect(h.audit.entries).toEqual([
        {
          actorId: null,
          action: 'AGENT_ATTRIBUTION_CREATED',
          entity: 'attribution',
          entityId: 'attribution-1',
          metadata: { source: 'CODE_AT_SIGNUP', needsReview: false },
        },
      ]);
    });

    it('is atomic: if the audit entry fails, no attribution is left', async () => {
      jest
        .spyOn(h.audit, 'record')
        .mockRejectedValueOnce(new Error('audit down'));
      await expect(attach()).rejects.toThrow('audit down');
      expect(await h.attributions.findByMemberId('m1')).toBeNull();
    });

    it("the credited member then appears in the agent's referrals, and in nobody else's", async () => {
      await attach();
      const claims = await h.claimsOf(await h.signInAs());
      const mine = await h.referrals.listReferrals(claims);
      expect(mine.items).toHaveLength(1);
      await h.seedAgent('ACTIVE', {
        id: 'agent-2',
        phoneE164: '+919000000001',
      });
      expect(await h.attributions.listByAgent('agent-2')).toHaveLength(0);
    });

    describe('a code that cannot be used is CODE_NOT_FOUND, whatever the reason', () => {
      it('unknown, inactive, and not-ACTIVE agents all give the identical error', async () => {
        await seedAgentWithCode('ACTIVE', {
          id: 'a2',
          phone: '+919000000001',
          code: 'NM2222AA',
          codeActive: false,
        });
        await seedAgentWithCode('SUSPENDED', {
          id: 'a3',
          phone: '+919000000002',
          code: 'NM3333BB',
        });
        await seedAgentWithCode('PENDING_APPROVAL', {
          id: 'a4',
          phone: '+919999999999',
          code: 'NM4444CC',
        });
        const errors: string[] = [];
        for (const code of ['NM9999ZZ', 'NM2222AA', 'NM3333BB', 'NM4444CC']) {
          h.seedMember(`probe-${code}`);
          const error = await attach(`probe-${code}`, code).catch(
            (e: unknown) => e,
          );
          expect(error).toMatchObject({ code: 'CODE_NOT_FOUND' });
          errors.push(JSON.stringify(error));
        }
        expect(new Set(errors).size).toBe(1);
        for (const code of ['NM9999ZZ', 'NM2222AA', 'NM3333BB', 'NM4444CC']) {
          expect(
            await h.attributions.findByMemberId(`probe-${code}`),
          ).toBeNull();
        }
      });
    });

    it.each(['', 'abc', 'NM00000O', 'NM7K2P9', 42, null, undefined])(
      'a code that is not well-formed (%p) is VALIDATION_FAILED',
      async (code) => {
        await expectServiceError(
          h.referralCodes.attachCode('m1', code),
          'VALIDATION_FAILED',
          { fields: ['code'] },
        );
      },
    );

    it('an unknown member is UNAUTHORIZED', async () => {
      await expectServiceError(attach('ghost'), 'UNAUTHORIZED');
    });

    describe('SELF-REFERRAL', () => {
      beforeEach(() => {
        // the agent signs up as a member with the same verified phone
        h.seedMember('self', { phoneHash: h.hasher.hash('PHONE', PHONE) });
      });

      it('an agent cannot credit their own phone: SELF_REFERRAL', async () => {
        await expectServiceError(attach('self'), 'SELF_REFERRAL');
      });

      it('keeps a REJECTED attribution for review, with an audit entry, and no credit', async () => {
        await attach('self').catch(() => undefined);
        const stored = await h.attributions.findByMemberId('self');
        expect(stored).toMatchObject({
          status: 'REJECTED',
          agentId: 'agent-1',
          needsReview: true,
        });
        expect(h.audit.entries).toEqual([
          expect.objectContaining({
            action: 'AGENT_ATTRIBUTION_REJECTED',
            metadata: { reason: 'SELF_REFERRAL' },
          }),
        ]);
      });

      it('only the self-referral is flagged: a normal attach is not', async () => {
        await attach('m1');
        expect(await h.attributions.findByMemberId('m1')).toMatchObject({
          status: 'ACTIVE',
          needsReview: false,
        });
      });

      it('the rejected row is never shown to the agent', async () => {
        await attach('self').catch(() => undefined);
        const claims = await h.claimsOf(await h.signInAs());
        await expect(h.referrals.listReferrals(claims)).resolves.toMatchObject({
          items: [],
        });
      });

      it('trying again stays SELF_REFERRAL and adds no second row', async () => {
        await attach('self').catch(() => undefined);
        await expectServiceError(attach('self'), 'SELF_REFERRAL');
        expect(await h.attributions.listByAgent('agent-1')).toHaveLength(1);
      });

      it('a self-referring member cannot then be credited to another agent', async () => {
        await seedAgentWithCode('ACTIVE', {
          id: 'a2',
          phone: '+919000000001',
          code: 'NM2222AA',
        });
        await attach('self').catch(() => undefined);
        await expectServiceError(
          attach('self', 'NM2222AA'),
          'ALREADY_ATTRIBUTED',
        );
      });

      it('an agent with a paused or ended account is not a self-referral target (CODE_NOT_FOUND first)', async () => {
        await h.agents.update('agent-1', { status: 'SUSPENDED' });
        await expectServiceError(attach('self'), 'CODE_NOT_FOUND');
      });

      it('a different phone is credited normally (control)', async () => {
        await expect(attach('m1')).resolves.toMatchObject({ attached: true });
      });
    });

    describe('first attribution wins', () => {
      it('a second attach of the same code is ALREADY_ATTRIBUTED', async () => {
        await attach();
        const create = jest.spyOn(h.attributions, 'create');
        await expectServiceError(attach(), 'ALREADY_ATTRIBUTED');
        // refused by the decision itself, before any write is attempted
        expect(create).not.toHaveBeenCalled();
      });

      it("another agent's code cannot replace the first", async () => {
        await seedAgentWithCode('ACTIVE', {
          id: 'a2',
          phone: '+919000000001',
          code: 'NM2222AA',
        });
        await attach();
        await expectServiceError(
          attach('m1', 'NM2222AA'),
          'ALREADY_ATTRIBUTED',
        );
        expect((await h.attributions.findByMemberId('m1'))!.agentId).toBe(
          'agent-1',
        );
        expect(await h.attributions.listByAgent('a2')).toHaveLength(0);
      });

      it('a phone already credited under another member id is ALREADY_ATTRIBUTED', async () => {
        h.seedMember('m2', { phoneHash: 'hash-of-m1' });
        await attach('m1');
        const create = jest.spyOn(h.attributions, 'create');
        await expectServiceError(attach('m2'), 'ALREADY_ATTRIBUTED');
        expect(create).not.toHaveBeenCalled();
      });

      it('two attaches at once for one member: one wins, the other is ALREADY_ATTRIBUTED, one row', async () => {
        const results = await Promise.allSettled([attach(), attach()]);
        expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
        const failed = results.find(
          (r) => r.status === 'rejected',
        ) as PromiseRejectedResult;
        expect(failed.reason).toMatchObject({ code: 'ALREADY_ATTRIBUTED' });
        expect(await h.attributions.listByAgent('agent-1')).toHaveLength(1);
      });

      it('a database duplicate (a race the checks missed) is ALREADY_ATTRIBUTED', async () => {
        jest
          .spyOn(h.attributions, 'create')
          .mockRejectedValueOnce(
            new AgentConflictError('DUPLICATE_ATTRIBUTION'),
          );
        await expectServiceError(attach(), 'ALREADY_ATTRIBUTED');
      });
    });

    it('a member who has already paid is ALREADY_PAID', async () => {
      h.seedMember('paid', { hasPaid: true });
      await expectServiceError(attach('paid'), 'ALREADY_PAID');
      expect(await h.attributions.findByMemberId('paid')).toBeNull();
    });

    describe('no verified phone: no credit, from any source', () => {
      beforeEach(() => h.seedMember('nophone', { phoneHash: null }));

      it.each(['CODE_AT_SIGNUP', 'LINK_OR_QR', 'ENTERED_AT_PAYMENT'] as const)(
        '%s is refused with PHONE_NOT_VERIFIED and nothing is written',
        async (source) => {
          const create = jest.spyOn(h.attributions, 'create');
          await expectServiceError(
            attach('nophone', CODE, source),
            'PHONE_NOT_VERIFIED',
          );
          expect(create).not.toHaveBeenCalled();
          expect(await h.attributions.findByMemberId('nophone')).toBeNull();
          expect(h.audit.entries).toHaveLength(0);
        },
      );
    });

    describe('rate limiting (per member and per code)', () => {
      it(`the ${IP_LIMIT + 1}th try by one member in the window is RATE_LIMITED`, async () => {
        for (let i = 0; i < IP_LIMIT; i++) {
          await attach('m1', `NM${i + 2}ZZZZZ`).catch(() => undefined);
        }
        await expectServiceError(attach('m1', 'NM9999ZZ'), 'RATE_LIMITED');
      });

      it('is counted per member, so another member is unaffected', async () => {
        h.seedMember('m3');
        for (let i = 0; i < IP_LIMIT; i++) {
          await attach('m1', `NM${i + 2}ZZZZZ`).catch(() => undefined);
        }
        await expect(attach('m3')).resolves.toMatchObject({ attached: true });
      });

      it('counts failed tries too (they are the ones being limited)', async () => {
        for (let i = 0; i < CODE_LIMIT; i++) {
          h.seedMember(`x${i}`);
          await attach(`x${i}`, 'NM9999ZZ').catch(() => undefined);
        }
        h.seedMember('x9');
        await expectServiceError(attach('x9', 'NM9999ZZ'), 'RATE_LIMITED');
      });

      it('a malformed code is refused before it is counted', async () => {
        for (let i = 0; i < IP_LIMIT + 2; i++) {
          await attach('m1', 'bad').catch(() => undefined);
        }
        expect(h.attempts.size).toBe(0);
        await expect(attach()).resolves.toMatchObject({ attached: true });
      });
    });
  });
});
