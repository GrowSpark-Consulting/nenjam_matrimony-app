import {
  CommissionTransitionInput,
  decideCommissionTransition,
  OpenCommissionStatus,
} from './decide-commission-transition';

const NOW = new Date('2026-10-27T10:00:00.000Z');
const PAST = new Date('2026-10-20T10:00:00.000Z');
const FUTURE = new Date('2026-11-03T10:00:00.000Z');

const input = (
  overrides: Partial<CommissionTransitionInput> = {},
): CommissionTransitionInput => ({
  status: 'ON_HOLD',
  now: NOW,
  holdUntil: PAST,
  agentStatus: 'ACTIVE',
  autoApprove: true,
  profileEligible: true,
  commissionBaseConfigured: true,
  ...overrides,
});

const ALL_STATUSES: OpenCommissionStatus[] = [
  'ON_HOLD',
  'AWAITING_VERIFICATION',
  'IN_REVIEW',
  'FROZEN',
  'READY',
];

describe('decideCommissionTransition', () => {
  describe('1. IN_REVIEW is left to the admin', () => {
    it('stays IN_REVIEW', () => {
      expect(
        decideCommissionTransition(input({ status: 'IN_REVIEW' })),
      ).toEqual({ next: 'IN_REVIEW', reason: 'ADMIN_REVIEW' });
    });

    it.each(['SUSPENDED', 'TERMINATED'])(
      'stays IN_REVIEW even for a %s agent (rule 1 beats rule 2)',
      (agentStatus) => {
        expect(
          decideCommissionTransition(
            input({ status: 'IN_REVIEW', agentStatus }),
          ),
        ).toEqual({ next: 'IN_REVIEW', reason: 'ADMIN_REVIEW' });
      },
    );

    it('stays IN_REVIEW whatever the other facts are', () => {
      expect(
        decideCommissionTransition(
          input({
            status: 'IN_REVIEW',
            commissionBaseConfigured: false,
            holdUntil: FUTURE,
            profileEligible: false,
          }),
        ),
      ).toEqual({ next: 'IN_REVIEW', reason: 'ADMIN_REVIEW' });
    });
  });

  describe('2. suspended or terminated agent freezes the commission', () => {
    it.each(
      ALL_STATUSES.filter((s) => s !== 'IN_REVIEW').map((s) => [s] as const),
    )('SUSPENDED agent: %s -> FROZEN', (status) => {
      expect(
        decideCommissionTransition(input({ status, agentStatus: 'SUSPENDED' })),
      ).toEqual({ next: 'FROZEN', reason: 'AGENT_SUSPENDED' });
    });

    it.each(
      ALL_STATUSES.filter((s) => s !== 'IN_REVIEW').map((s) => [s] as const),
    )('TERMINATED agent: %s -> FROZEN', (status) => {
      expect(
        decideCommissionTransition(
          input({ status, agentStatus: 'TERMINATED' }),
        ),
      ).toEqual({ next: 'FROZEN', reason: 'AGENT_TERMINATED' });
    });

    it('beats READY (rule 2 before rule 3)', () => {
      expect(
        decideCommissionTransition(
          input({ status: 'READY', agentStatus: 'SUSPENDED' }),
        ),
      ).toEqual({ next: 'FROZEN', reason: 'AGENT_SUSPENDED' });
    });

    it('beats a missing commission base and a running hold', () => {
      expect(
        decideCommissionTransition(
          input({
            agentStatus: 'SUSPENDED',
            commissionBaseConfigured: false,
            holdUntil: FUTURE,
          }),
        ),
      ).toEqual({ next: 'FROZEN', reason: 'AGENT_SUSPENDED' });
    });

    it.each(['PENDING_APPROVAL', 'REJECTED', 'something-new'])(
      'does not freeze for agentStatus %s',
      (agentStatus) => {
        expect(decideCommissionTransition(input({ agentStatus })).next).toBe(
          'APPROVED',
        );
      },
    );
  });

  describe('3. READY waits for an admin', () => {
    it('stays READY', () => {
      expect(decideCommissionTransition(input({ status: 'READY' }))).toEqual({
        next: 'READY',
        reason: 'AWAITING_ADMIN',
      });
    });

    it('stays READY even with auto-approve on', () => {
      expect(
        decideCommissionTransition(
          input({ status: 'READY', autoApprove: true }),
        ),
      ).toEqual({ next: 'READY', reason: 'AWAITING_ADMIN' });
    });

    it('stays READY before the base check', () => {
      expect(
        decideCommissionTransition(
          input({ status: 'READY', commissionBaseConfigured: false }),
        ),
      ).toEqual({ next: 'READY', reason: 'AWAITING_ADMIN' });
    });
  });

  describe('4. commission base not configured', () => {
    it.each(
      ALL_STATUSES.filter((s) => s !== 'IN_REVIEW' && s !== 'READY').map(
        (s) => [s] as const,
      ),
    )('leaves %s unchanged', (status) => {
      expect(
        decideCommissionTransition(
          input({ status, commissionBaseConfigured: false }),
        ),
      ).toEqual({ next: status, reason: 'BASE_NOT_SET' });
    });

    it('beats a running hold', () => {
      expect(
        decideCommissionTransition(
          input({ commissionBaseConfigured: false, holdUntil: FUTURE }),
        ),
      ).toEqual({ next: 'ON_HOLD', reason: 'BASE_NOT_SET' });
    });
  });

  describe('5. hold period', () => {
    it('is ON_HOLD while now < holdUntil', () => {
      expect(decideCommissionTransition(input({ holdUntil: FUTURE }))).toEqual({
        next: 'ON_HOLD',
        reason: 'HOLD_RUNNING',
      });
    });

    it('is ON_HOLD one millisecond before holdUntil', () => {
      expect(
        decideCommissionTransition(
          input({ holdUntil: new Date(NOW.getTime() + 1) }),
        ),
      ).toEqual({ next: 'ON_HOLD', reason: 'HOLD_RUNNING' });
    });

    it('is over exactly at now === holdUntil', () => {
      expect(
        decideCommissionTransition(
          input({ holdUntil: new Date(NOW.getTime()) }),
        ),
      ).toEqual({ next: 'APPROVED', reason: 'AUTO_APPROVED' });
    });

    it('is over after holdUntil', () => {
      expect(decideCommissionTransition(input({ holdUntil: PAST })).next).toBe(
        'APPROVED',
      );
    });

    it('beats an ineligible profile', () => {
      expect(
        decideCommissionTransition(
          input({ holdUntil: FUTURE, profileEligible: false }),
        ),
      ).toEqual({ next: 'ON_HOLD', reason: 'HOLD_RUNNING' });
    });

    it('moves AWAITING_VERIFICATION back to ON_HOLD if the hold is running', () => {
      expect(
        decideCommissionTransition(
          input({ status: 'AWAITING_VERIFICATION', holdUntil: FUTURE }),
        ),
      ).toEqual({ next: 'ON_HOLD', reason: 'HOLD_RUNNING' });
    });
  });

  describe('6. profile not eligible', () => {
    it.each(['ON_HOLD', 'AWAITING_VERIFICATION', 'FROZEN'] as const)(
      '%s -> AWAITING_VERIFICATION once the hold is over',
      (status) => {
        expect(
          decideCommissionTransition(input({ status, profileEligible: false })),
        ).toEqual({
          next: 'AWAITING_VERIFICATION',
          reason: 'PROFILE_NOT_VERIFIED',
        });
      },
    );

    it('applies whatever autoApprove is', () => {
      expect(
        decideCommissionTransition(
          input({ profileEligible: false, autoApprove: false }),
        ).next,
      ).toBe('AWAITING_VERIFICATION');
    });
  });

  describe('7. approve or ready', () => {
    it.each(['ON_HOLD', 'AWAITING_VERIFICATION', 'FROZEN'] as const)(
      '%s -> APPROVED when autoApprove is on',
      (status) => {
        expect(decideCommissionTransition(input({ status }))).toEqual({
          next: 'APPROVED',
          reason: 'AUTO_APPROVED',
        });
      },
    );

    it.each(['ON_HOLD', 'AWAITING_VERIFICATION', 'FROZEN'] as const)(
      '%s -> READY when autoApprove is off',
      (status) => {
        expect(
          decideCommissionTransition(input({ status, autoApprove: false })),
        ).toEqual({ next: 'READY', reason: 'READY_FOR_ADMIN' });
      },
    );
  });

  describe('a FROZEN commission whose agent is ACTIVE again', () => {
    it('is evaluated from rule 4 on', () => {
      expect(decideCommissionTransition(input({ status: 'FROZEN' })).next).toBe(
        'APPROVED',
      );
      expect(
        decideCommissionTransition(
          input({ status: 'FROZEN', holdUntil: FUTURE }),
        ),
      ).toEqual({ next: 'ON_HOLD', reason: 'HOLD_RUNNING' });
      expect(
        decideCommissionTransition(
          input({ status: 'FROZEN', commissionBaseConfigured: false }),
        ),
      ).toEqual({ next: 'FROZEN', reason: 'BASE_NOT_SET' });
    });
  });

  describe('invalid dates', () => {
    it('throws on an invalid now', () => {
      expect(() =>
        decideCommissionTransition(input({ now: new Date('nope') })),
      ).toThrow(RangeError);
    });

    it('throws on an invalid holdUntil instead of approving', () => {
      expect(() =>
        decideCommissionTransition(input({ holdUntil: new Date('nope') })),
      ).toThrow(RangeError);
    });
  });
});
