import {
  agentCapabilitiesFor,
  AgentCapabilities,
  AgentStatus,
  canTransitionAgentStatus,
  REJECTED_MAY_REAPPLY,
} from './agent-status';

const STATUSES: AgentStatus[] = [
  'PENDING_APPROVAL',
  'ACTIVE',
  'REJECTED',
  'SUSPENDED',
  'TERMINATED',
];

describe('canTransitionAgentStatus', () => {
  describe('allowed moves', () => {
    it.each([
      ['PENDING_APPROVAL', 'ACTIVE'],
      ['PENDING_APPROVAL', 'REJECTED'],
      ['ACTIVE', 'SUSPENDED'],
      ['SUSPENDED', 'ACTIVE'],
      ['ACTIVE', 'TERMINATED'],
      ['SUSPENDED', 'TERMINATED'],
    ])('%s -> %s', (from, to) => {
      expect(canTransitionAgentStatus(from, to)).toEqual({ allowed: true });
    });
  });

  describe('re-apply (pending decision)', () => {
    it('REJECTED -> PENDING_APPROVAL follows REJECTED_MAY_REAPPLY', () => {
      expect(
        canTransitionAgentStatus('REJECTED', 'PENDING_APPROVAL').allowed,
      ).toBe(REJECTED_MAY_REAPPLY);
    });

    it('is currently allowed, as the API contract assumes', () => {
      expect(REJECTED_MAY_REAPPLY).toBe(true);
    });
  });

  describe('refused moves', () => {
    it.each([
      ['PENDING_APPROVAL', 'SUSPENDED'],
      ['PENDING_APPROVAL', 'TERMINATED'],
      ['ACTIVE', 'PENDING_APPROVAL'],
      ['ACTIVE', 'REJECTED'],
      ['SUSPENDED', 'PENDING_APPROVAL'],
      ['SUSPENDED', 'REJECTED'],
      ['REJECTED', 'ACTIVE'],
      ['REJECTED', 'SUSPENDED'],
      ['REJECTED', 'TERMINATED'],
    ])('%s -> %s', (from, to) => {
      expect(canTransitionAgentStatus(from, to)).toEqual({
        allowed: false,
        reason: 'TRANSITION_NOT_ALLOWED',
      });
    });
  });

  describe('TERMINATED is final', () => {
    it.each(STATUSES.filter((s) => s !== 'TERMINATED'))(
      'TERMINATED -> %s',
      (to) => {
        expect(canTransitionAgentStatus('TERMINATED', to)).toEqual({
          allowed: false,
          reason: 'TERMINATED_IS_FINAL',
        });
      },
    );
  });

  describe('no-op moves', () => {
    it.each(STATUSES)('%s -> itself', (status) => {
      expect(canTransitionAgentStatus(status, status)).toEqual({
        allowed: false,
        reason: 'SAME_STATUS',
      });
    });
  });

  describe('unknown statuses', () => {
    it.each([
      ['ACTIVE', 'DELETED'],
      ['DELETED', 'ACTIVE'],
      ['', 'ACTIVE'],
      ['ACTIVE', ''],
      ['active', 'SUSPENDED'],
      ['toString', 'ACTIVE'],
      ['ACTIVE', 'constructor'],
    ])('%s -> %s', (from, to) => {
      expect(canTransitionAgentStatus(from, to)).toEqual({
        allowed: false,
        reason: 'UNKNOWN_STATUS',
      });
    });
  });

  it('covers every ordered pair of statuses exactly once', () => {
    const allowed: string[] = [];
    for (const from of STATUSES) {
      for (const to of STATUSES) {
        if (canTransitionAgentStatus(from, to).allowed)
          allowed.push(`${from}>${to}`);
      }
    }
    expect(allowed.sort()).toEqual(
      [
        'PENDING_APPROVAL>ACTIVE',
        'PENDING_APPROVAL>REJECTED',
        'ACTIVE>SUSPENDED',
        'SUSPENDED>ACTIVE',
        'ACTIVE>TERMINATED',
        'SUSPENDED>TERMINATED',
        ...(REJECTED_MAY_REAPPLY ? ['REJECTED>PENDING_APPROVAL'] : []),
      ].sort(),
    );
  });
});

describe('agentCapabilitiesFor', () => {
  const allowedKeys = (status: string): string[] =>
    Object.entries(agentCapabilitiesFor(status))
      .filter(([, allowed]) => allowed)
      .map(([key]) => key)
      .sort();

  const SESSION = [
    'logout',
    'refreshSession',
    'registerDevice',
    'viewConfig',
    'viewStatus',
  ];

  it('PENDING_APPROVAL sees only status and config (plus session and push)', () => {
    expect(allowedKeys('PENDING_APPROVAL')).toEqual(SESSION);
  });

  it('REJECTED is the same, plus re-apply when allowed', () => {
    expect(allowedKeys('REJECTED')).toEqual(
      [...SESSION, ...(REJECTED_MAY_REAPPLY ? ['apply'] : [])].sort(),
    );
  });

  it('ACTIVE can do everything except apply', () => {
    const caps = agentCapabilitiesFor('ACTIVE');
    expect(caps.apply).toBe(false);
    const rest: Partial<AgentCapabilities> = { ...caps };
    delete rest.apply;
    expect(Object.values(rest).every(Boolean)).toBe(true);
  });

  it('SUSPENDED reads everything but cannot share links, edit payout details or earn', () => {
    expect(allowedKeys('SUSPENDED')).toEqual(
      [
        ...SESSION,
        'viewReferrals',
        'viewReferralLinks',
        'viewCommissions',
        'viewBalance',
        'viewPayouts',
      ].sort(),
    );
    const caps = agentCapabilitiesFor('SUSPENDED');
    expect(caps.shareReferralLinks).toBe(false);
    expect(caps.editPayoutDetails).toBe(false);
    expect(caps.earnNewCredit).toBe(false);
    expect(caps.addMembers).toBe(false);
  });

  it('TERMINATED is read-only: status, config, commissions, balance, payouts, refresh, logout', () => {
    expect(allowedKeys('TERMINATED')).toEqual(
      [
        'viewStatus',
        'viewConfig',
        'viewCommissions',
        'viewBalance',
        'viewPayouts',
        'refreshSession',
        'logout',
      ].sort(),
    );
  });

  it('TERMINATED has no links, referrals, devices, edits, credit or members', () => {
    const caps = agentCapabilitiesFor('TERMINATED');
    expect(caps).toMatchObject({
      viewReferrals: false,
      viewReferralLinks: false,
      shareReferralLinks: false,
      registerDevice: false,
      editPayoutDetails: false,
      earnNewCredit: false,
      addMembers: false,
      apply: false,
    });
  });

  it.each(['', 'active', 'DELETED', 'toString', '__proto__'])(
    'an unknown status (%p) may do nothing',
    (status) => {
      expect(allowedKeys(status)).toEqual([]);
    },
  );

  it('returns a copy, so callers cannot change the table', () => {
    const caps = agentCapabilitiesFor('TERMINATED');
    caps.editPayoutDetails = true;
    expect(agentCapabilitiesFor('TERMINATED').editPayoutDetails).toBe(false);
  });

  it('only ACTIVE earns new credit, shares links or edits payout details', () => {
    for (const status of STATUSES) {
      const caps = agentCapabilitiesFor(status);
      const isActive = status === 'ACTIVE';
      expect(caps.earnNewCredit).toBe(isActive);
      expect(caps.shareReferralLinks).toBe(isActive);
      expect(caps.editPayoutDetails).toBe(isActive);
      expect(caps.addMembers).toBe(isActive);
    }
  });

  it('every status can sign out; all but TERMINATED can register a device', () => {
    for (const status of STATUSES) {
      expect(agentCapabilitiesFor(status).logout).toBe(true);
      expect(agentCapabilitiesFor(status).registerDevice).toBe(
        status !== 'TERMINATED',
      );
    }
  });
});
