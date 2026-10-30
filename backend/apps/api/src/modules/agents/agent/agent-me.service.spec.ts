import { AGENT_SEAL_PURPOSES } from '../ports/agent-secret-sealer.port';
import type { AgentAccessClaims } from '../auth/agent-access-claims';
import {
  AgentHarness,
  AUTH_OPTIONS,
  expectServiceError,
  makeAgentHarness,
  PHONE,
  START,
} from '../testing/agent-test-harness';
import { AgentCapabilities, agentCapabilitiesFor } from './agent-status';

const STATUSES = [
  'PENDING_APPROVAL',
  'REJECTED',
  'ACTIVE',
  'SUSPENDED',
  'TERMINATED',
] as const;

const UPI = { upi: { vpa: 'ravi@okbank' } };
const BANK = {
  bank: {
    accountHolderName: 'Ravi Kumar',
    accountNumber: '123456789012',
    ifsc: 'HDFC0001234',
  },
};

describe('AgentMeService', () => {
  let h: AgentHarness;
  beforeEach(() => {
    h = makeAgentHarness();
  });

  /** Seeds an agent in `status` and signs in as them. */
  const asAgent = async (status: string, overrides = {}) => {
    await h.seedAgent(status, overrides);
    return h.claimsOf(await h.signInAs());
  };

  describe('getProfile', () => {
    it.each([
      ['PENDING_APPROVAL', 'Under review'],
      ['REJECTED', 'Rejected'],
      ['ACTIVE', 'Active'],
      ['SUSPENDED', 'Paused'],
      ['TERMINATED', 'Terminated'],
    ])('a %s agent sees their profile (%s)', async (status, label) => {
      const profile = await h.me.getProfile(await asAgent(status));
      expect(profile).toMatchObject({
        id: 'agent-1',
        name: 'Ravi Kumar',
        status,
        statusLabel: { en: label, ta: '<to be supplied>' },
        city: 'Coimbatore',
        state: 'Tamil Nadu',
      });
    });

    it('shows the rejection reason only to a REJECTED agent', async () => {
      const reason = { rejectionReason: 'Incomplete details' };
      expect(
        (await h.me.getProfile(await asAgent('REJECTED', reason)))
          .rejectionReason,
      ).toBe('Incomplete details');
      const other = makeAgentHarness();
      await other.seedAgent('SUSPENDED', reason);
      const claims = await other.claimsOf(await other.signInAs());
      expect((await other.me.getProfile(claims)).rejectionReason).toBeNull();
    });

    it('is masked: phone, PAN and everything sealed or hashed stay out', async () => {
      const claims = await asAgent('ACTIVE', {
        panLast4: '234F',
        panSealed: h.sealer.seal(
          AGENT_SEAL_PURPOSES.payoutDetails,
          'ABCDE1234F',
        ),
      });
      const profile = await h.me.getProfile(claims);
      expect(profile.phoneMasked).toBe('+91 98***210');
      expect(profile.panLast4).toBe('234F');
      const json = JSON.stringify(profile);
      expect(json).not.toContain('9876543210');
      expect(json).not.toContain('ABCDE1234F');
      expect(json).not.toContain('v1:');
      expect(json).not.toContain(h.hasher.hash('PHONE', PHONE));
      expect(Object.keys(profile).sort()).toEqual(
        [
          'approvedAt',
          'city',
          'id',
          'name',
          'panLast4',
          'payoutDetailsSet',
          'phoneMasked',
          'primaryCode',
          'rejectionReason',
          'state',
          'status',
          'statusLabel',
        ].sort(),
      );
    });

    it('shows the approval date and the primary code', async () => {
      const claims = await asAgent('ACTIVE');
      await h.codes.create({
        id: 'code-1',
        agentId: 'agent-1',
        code: 'NM7K2P9X',
        isPrimary: true,
        isActive: true,
        createdAt: START,
      });
      expect(await h.me.getProfile(claims)).toMatchObject({
        approvedAt: '2026-10-28',
        primaryCode: 'NM7K2P9X',
      });
    });

    it('an applicant has no agent yet: AGENT_NOT_FOUND', async () => {
      const claims = await h.claimsOf(await h.signInAs());
      await expectServiceError(h.me.getProfile(claims), 'AGENT_NOT_FOUND');
    });

    it('a token scope that is not AGENT or APPLICANT is UNAUTHORIZED', async () => {
      const claims = { ...(await asAgent('ACTIVE')), scope: 'ADMIN' as never };
      await expectServiceError(h.me.getProfile(claims), 'UNAUTHORIZED');
    });

    it('an agent id with no record is AGENT_NOT_FOUND', async () => {
      const claims: AgentAccessClaims = {
        ...(await asAgent('ACTIVE')),
        sub: 'ghost',
      };
      await expectServiceError(h.me.getProfile(claims), 'AGENT_NOT_FOUND');
    });

    it('a status the program does not know is refused with that status', async () => {
      const claims = await asAgent('ACTIVE');
      await h.agents.update('agent-1', { status: 'WEIRD' as never });
      await expectServiceError(h.me.getProfile(claims), 'AGENT_NOT_ACTIVE', {
        agentStatus: 'WEIRD',
      });
    });
  });

  describe('capabilities per status', () => {
    const expected: Record<
      (typeof STATUSES)[number],
      Partial<AgentCapabilities>
    > = {
      PENDING_APPROVAL: {
        viewStatus: true,
        viewConfig: true,
        refreshSession: true,
        logout: true,
        viewReferrals: false,
        viewReferralLinks: false,
        shareReferralLinks: false,
        viewCommissions: false,
        viewBalance: false,
        viewPayouts: false,
        editPayoutDetails: false,
        earnNewCredit: false,
        addMembers: false,
        apply: false,
      },
      REJECTED: {
        viewStatus: true,
        refreshSession: true,
        apply: true,
        viewReferrals: false,
        shareReferralLinks: false,
        editPayoutDetails: false,
        earnNewCredit: false,
      },
      ACTIVE: {
        viewStatus: true,
        viewReferrals: true,
        viewReferralLinks: true,
        shareReferralLinks: true,
        viewCommissions: true,
        viewBalance: true,
        viewPayouts: true,
        editPayoutDetails: true,
        earnNewCredit: true,
        addMembers: true,
        apply: false,
      },
      SUSPENDED: {
        viewStatus: true,
        viewReferrals: true,
        viewReferralLinks: true,
        viewCommissions: true,
        viewBalance: true,
        viewPayouts: true,
        shareReferralLinks: false,
        editPayoutDetails: false,
        earnNewCredit: false,
        addMembers: false,
        apply: false,
      },
      TERMINATED: {
        viewStatus: true,
        viewConfig: true,
        refreshSession: true,
        logout: true,
        viewCommissions: true,
        viewBalance: true,
        viewPayouts: true,
        viewReferrals: false,
        viewReferralLinks: false,
        shareReferralLinks: false,
        editPayoutDetails: false,
        earnNewCredit: false,
        addMembers: false,
        apply: false,
      },
    };

    it.each(STATUSES)(
      '%s: the table matches what the contract says',
      async (status) => {
        const caps = await h.me.capabilities(await asAgent(status));
        expect(caps).toMatchObject(expected[status]);
        expect(caps).toEqual(agentCapabilitiesFor(status));
      },
    );

    it.each(STATUSES)(
      '%s may view its status (everyone has to see it)',
      async (status) => {
        await expect(
          h.me.assertCan(await asAgent(status), 'viewStatus'),
        ).resolves.toMatchObject({ id: 'agent-1', status });
      },
    );

    it.each(STATUSES)(
      '%s: assertCan passes only where the table allows (share links, payout edit)',
      async (status) => {
        const claims = await asAgent(status);
        for (const capability of [
          'shareReferralLinks',
          'editPayoutDetails',
        ] as const) {
          const allowed = agentCapabilitiesFor(status)[capability];
          const attempt = h.me.assertCan(claims, capability);
          if (allowed) await expect(attempt).resolves.toBeDefined();
          else
            await expectServiceError(attempt, 'AGENT_NOT_ACTIVE', {
              agentStatus: status,
            });
        }
      },
    );

    it('only an ACTIVE agent can share links or edit payout details', () => {
      for (const status of STATUSES) {
        const caps = agentCapabilitiesFor(status);
        expect(caps.shareReferralLinks).toBe(status === 'ACTIVE');
        expect(caps.editPayoutDetails).toBe(status === 'ACTIVE');
      }
    });

    it('an applicant is UNAUTHORIZED for an agent endpoint', async () => {
      const claims = await h.claimsOf(await h.signInAs());
      await expectServiceError(
        h.me.assertCan(claims, 'viewReferrals'),
        'UNAUTHORIZED',
      );
    });
  });

  describe('updatePayoutDetails', () => {
    it('stores UPI details sealed and returns a masked summary', async () => {
      const claims = await asAgent('ACTIVE');
      const summary = await h.me.updatePayoutDetails(claims, UPI);
      expect(summary).toEqual({ method: 'UPI', display: 'r***@okbank' });
      const stored = await h.payoutDetails.find('agent-1');
      expect(stored!.method).toBe('UPI');
      expect(stored!.detailsSealed).not.toContain('ravi@okbank');
      expect(
        JSON.parse(
          h.sealer.open(
            AGENT_SEAL_PURPOSES.payoutDetails,
            stored!.detailsSealed,
          ),
        ),
      ).toEqual({
        vpa: 'ravi@okbank',
      });
    });

    it('stores bank details sealed and returns a masked summary', async () => {
      const claims = await asAgent('ACTIVE');
      const summary = await h.me.updatePayoutDetails(claims, BANK);
      expect(summary).toEqual({ method: 'BANK', display: 'HDFC ****9012' });
      const stored = await h.payoutDetails.find('agent-1');
      expect(stored!.detailsSealed).not.toContain('123456789012');
      expect(
        JSON.parse(
          h.sealer.open(
            AGENT_SEAL_PURPOSES.payoutDetails,
            stored!.detailsSealed,
          ),
        ),
      ).toEqual({
        accountHolderName: 'Ravi Kumar',
        accountNumber: '123456789012',
        ifsc: 'HDFC0001234',
      });
    });

    it('normalises what it stores (case, spaces)', async () => {
      const claims = await asAgent('ACTIVE');
      await h.me.updatePayoutDetails(claims, { upi: { vpa: ' Ravi@OkBank ' } });
      expect(
        JSON.parse(
          h.sealer.open(
            AGENT_SEAL_PURPOSES.payoutDetails,
            (await h.payoutDetails.find('agent-1'))!.detailsSealed,
          ),
        ),
      ).toEqual({ vpa: 'ravi@okbank' });
      await h.me.updatePayoutDetails(claims, {
        bank: {
          accountHolderName: '  Ravi Kumar ',
          accountNumber: ' 123456789012 ',
          ifsc: 'hdfc0001234',
        },
      });
      expect(
        JSON.parse(
          h.sealer.open(
            AGENT_SEAL_PURPOSES.payoutDetails,
            (await h.payoutDetails.find('agent-1'))!.detailsSealed,
          ),
        ),
      ).toEqual({
        accountHolderName: 'Ravi Kumar',
        accountNumber: '123456789012',
        ifsc: 'HDFC0001234',
      });
    });

    it('output and audit never hold the full values', async () => {
      const claims = await asAgent('ACTIVE');
      const summary = await h.me.updatePayoutDetails(claims, BANK);
      const everything = JSON.stringify([summary, h.audit.entries]);
      for (const secret of ['123456789012', 'HDFC0001234', 'Ravi Kumar']) {
        expect(everything).not.toContain(secret);
      }
      const upiSummary = await h.me.updatePayoutDetails(claims, UPI);
      expect(JSON.stringify(upiSummary)).not.toContain('ravi@okbank');
    });

    it('clears verification and records the change time', async () => {
      const claims = await asAgent('ACTIVE');
      await h.payoutDetails.save({
        agentId: 'agent-1',
        method: 'UPI',
        detailsSealed: h.sealer.seal(
          AGENT_SEAL_PURPOSES.payoutDetails,
          '{"vpa":"old@okbank"}',
        ),
        display: 'o***@okbank',
        verifiedAt: START,
        changedAt: START,
      });
      h.clock.advance(3_600_000);
      await h.me.updatePayoutDetails(claims, UPI);
      const stored = await h.payoutDetails.find('agent-1');
      expect(stored!.verifiedAt).toBeNull();
      expect(stored!.changedAt).toEqual(h.clock.now());
      expect(stored!.changedAt.getTime()).toBe(START.getTime() + 3_600_000);
    });

    it('every change restarts the wait, even to the same details', async () => {
      const claims = await asAgent('ACTIVE');
      await h.me.updatePayoutDetails(claims, UPI);
      h.clock.advance(7_200_000);
      await h.me.updatePayoutDetails(claims, UPI);
      expect((await h.payoutDetails.find('agent-1'))!.changedAt).toEqual(
        h.clock.now(),
      );
    });

    it('switching method replaces the record (one per agent)', async () => {
      const claims = await asAgent('ACTIVE');
      await h.me.updatePayoutDetails(claims, UPI);
      await h.me.updatePayoutDetails(claims, BANK);
      expect((await h.payoutDetails.find('agent-1'))!.method).toBe('BANK');
    });

    it('marks the profile payoutDetailsSet', async () => {
      const claims = await asAgent('ACTIVE');
      expect((await h.me.getProfile(claims)).payoutDetailsSet).toBe(false);
      await h.me.updatePayoutDetails(claims, UPI);
      expect((await h.me.getProfile(claims)).payoutDetailsSet).toBe(true);
    });

    it('writes one audit entry with the method only', async () => {
      const claims = await asAgent('ACTIVE');
      await h.me.updatePayoutDetails(claims, UPI);
      expect(h.audit.entries).toEqual([
        {
          actorId: 'agent-1',
          action: 'AGENT_PAYOUT_DETAILS_CHANGED',
          entity: 'agent',
          entityId: 'agent-1',
          metadata: { method: 'UPI' },
        },
      ]);
    });

    it('is atomic: if the audit entry cannot be written, nothing changes', async () => {
      const claims = await asAgent('ACTIVE');
      jest
        .spyOn(h.audit, 'record')
        .mockRejectedValueOnce(new Error('audit down'));
      await expect(h.me.updatePayoutDetails(claims, UPI)).rejects.toThrow(
        'audit down',
      );
      expect(await h.payoutDetails.find('agent-1')).toBeNull();
      expect((await h.agents.findById('agent-1'))!.payoutDetailsSet).toBe(
        false,
      );
    });

    it.each(['PENDING_APPROVAL', 'REJECTED', 'SUSPENDED', 'TERMINATED'])(
      'a %s agent is refused (AGENT_NOT_ACTIVE with the status) and nothing is stored',
      async (status) => {
        const claims = await asAgent(status);
        await expectServiceError(
          h.me.updatePayoutDetails(claims, UPI),
          'AGENT_NOT_ACTIVE',
          { agentStatus: status },
        );
        expect(await h.payoutDetails.find('agent-1')).toBeNull();
        expect(h.audit.entries).toHaveLength(0);
      },
    );

    it('status is judged before the body: a paused agent sending nonsense gets 403, not 400', async () => {
      const claims = await asAgent('SUSPENDED');
      await expectServiceError(
        h.me.updatePayoutDetails(claims, {}),
        'AGENT_NOT_ACTIVE',
      );
    });

    it('an applicant is UNAUTHORIZED', async () => {
      const claims = await h.claimsOf(await h.signInAs());
      await expectServiceError(
        h.me.updatePayoutDetails(claims, UPI),
        'UNAUTHORIZED',
      );
    });

    it('is refused if the agent is paused between the check and the write', async () => {
      const claims = await asAgent('ACTIVE');
      const active = await h.agents.findById('agent-1');
      jest
        .spyOn(h.agents, 'findById')
        .mockResolvedValueOnce(active)
        .mockResolvedValueOnce({ ...active!, status: 'SUSPENDED' });
      await expectServiceError(
        h.me.updatePayoutDetails(claims, UPI),
        'AGENT_NOT_ACTIVE',
        { agentStatus: 'SUSPENDED' },
      );
      expect(await h.payoutDetails.find('agent-1')).toBeNull();
    });

    describe('validation', () => {
      const run = async (input: unknown) =>
        h.me.updatePayoutDetails(await asAgent('ACTIVE'), input as never);

      it.each([
        [{}, ['upi', 'bank']],
        [{ upi: UPI.upi, bank: BANK.bank }, ['upi', 'bank']],
        [undefined, ['upi', 'bank']],
        [{ upi: { vpa: 'not a upi' } }, ['upi']],
        [{ upi: { vpa: '' } }, ['upi']],
        [{ upi: {} }, ['upi']],
        [{ upi: { vpa: 42 } }, ['upi']],
        [
          { bank: { ...BANK.bank, accountHolderName: '' } },
          ['bank.accountHolderName'],
        ],
        [
          { bank: { ...BANK.bank, accountHolderName: 'x'.repeat(101) } },
          ['bank.accountHolderName'],
        ],
        [
          { bank: { ...BANK.bank, accountNumber: '12345678' } },
          ['bank.accountNumber'],
        ],
        [
          { bank: { ...BANK.bank, accountNumber: '12345678901234567890' } },
          ['bank.accountNumber'],
        ],
        [
          { bank: { ...BANK.bank, accountNumber: '12345678901A' } },
          ['bank.accountNumber'],
        ],
        [{ bank: { ...BANK.bank, ifsc: 'HDFC1001234' } }, ['bank.ifsc']],
        [{ bank: { ...BANK.bank, ifsc: 'HDF0001234' } }, ['bank.ifsc']],
        [
          { bank: { accountHolderName: '', accountNumber: 'x', ifsc: 'y' } },
          ['bank.accountHolderName', 'bank.accountNumber', 'bank.ifsc'],
        ],
        [
          { bank: {} },
          ['bank.accountHolderName', 'bank.accountNumber', 'bank.ifsc'],
        ],
      ])('refuses %j', async (input, fields) => {
        await expectServiceError(run(input), 'VALIDATION_FAILED', { fields });
        expect(await h.payoutDetails.find('agent-1')).toBeNull();
        expect(h.audit.entries).toHaveLength(0);
      });

      it('never puts a bad value in the error', async () => {
        const error = await run({ upi: { vpa: 'SECRET-VALUE-XYZ' } }).catch(
          (e: unknown) => e,
        );
        expect(JSON.stringify(error)).not.toContain('SECRET-VALUE-XYZ');
        expect((error as Error).message).not.toContain('SECRET-VALUE-XYZ');
      });

      it('accepts the shortest and longest account numbers', async () => {
        const claims = await asAgent('ACTIVE');
        for (const accountNumber of ['123456789', '123456789012345678']) {
          await expect(
            h.me.updatePayoutDetails(claims, {
              bank: { ...BANK.bank, accountNumber },
            }),
          ).resolves.toMatchObject({ method: 'BANK' });
        }
      });
    });
  });

  it('uses the same issuer settings as sign-in (sanity: a signed-in token is what is verified)', async () => {
    const claims = await asAgent('ACTIVE');
    expect(claims.iss).toBe(AUTH_OPTIONS.issuer);
    expect(claims.aud).toBe(AUTH_OPTIONS.audience);
  });
});
