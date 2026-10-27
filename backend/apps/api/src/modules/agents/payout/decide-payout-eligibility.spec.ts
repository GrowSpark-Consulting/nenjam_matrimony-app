import {
  decidePayoutEligibility,
  PayoutEligibilityInput,
} from './decide-payout-eligibility';

const NOW = new Date('2026-10-27T10:00:00.000Z');

const input = (
  overrides: Partial<PayoutEligibilityInput> = {},
): PayoutEligibilityInput => ({
  agentStatus: 'ACTIVE',
  panVerified: true,
  payoutDetailsVerified: true,
  payoutDetailsChangedAt: new Date('2026-10-20T10:00:00.000Z'),
  waitHours: 24,
  now: NOW,
  balancePaise: 60_000,
  minimumPaise: 50_000,
  hasPayoutForPeriod: false,
  ...overrides,
});

describe('decidePayoutEligibility', () => {
  it('is eligible when everything is in order', () => {
    expect(decidePayoutEligibility(input())).toEqual({
      eligible: true,
      reasons: [],
    });
  });

  describe('AGENT_NOT_PAYABLE', () => {
    it.each(['ACTIVE', 'TERMINATED'])('%s is payable', (agentStatus) => {
      expect(decidePayoutEligibility(input({ agentStatus })).eligible).toBe(
        true,
      );
    });

    it.each(['SUSPENDED', 'PENDING_APPROVAL', 'REJECTED', 'unknown', ''])(
      '%s is not payable',
      (agentStatus) => {
        expect(decidePayoutEligibility(input({ agentStatus }))).toEqual({
          eligible: false,
          reasons: ['AGENT_NOT_PAYABLE'],
        });
      },
    );
  });

  it('PAN_NOT_VERIFIED', () => {
    expect(decidePayoutEligibility(input({ panVerified: false }))).toEqual({
      eligible: false,
      reasons: ['PAN_NOT_VERIFIED'],
    });
  });

  it('DETAILS_NOT_VERIFIED', () => {
    expect(
      decidePayoutEligibility(input({ payoutDetailsVerified: false })),
    ).toEqual({ eligible: false, reasons: ['DETAILS_NOT_VERIFIED'] });
  });

  describe('WAIT_NOT_OVER', () => {
    const changed = new Date('2026-10-26T10:00:00.000Z'); // 24h before NOW

    it('is over exactly when now === changedAt + waitHours', () => {
      expect(
        decidePayoutEligibility(
          input({ payoutDetailsChangedAt: changed, waitHours: 24 }),
        ).eligible,
      ).toBe(true);
    });

    it('is not over one millisecond earlier', () => {
      expect(
        decidePayoutEligibility(
          input({
            payoutDetailsChangedAt: new Date(changed.getTime() + 1),
            waitHours: 24,
          }),
        ),
      ).toEqual({ eligible: false, reasons: ['WAIT_NOT_OVER'] });
    });

    it('is not over for a just-changed detail', () => {
      expect(
        decidePayoutEligibility(input({ payoutDetailsChangedAt: NOW })),
      ).toEqual({ eligible: false, reasons: ['WAIT_NOT_OVER'] });
    });

    it('does not apply when the details were never changed', () => {
      expect(
        decidePayoutEligibility(input({ payoutDetailsChangedAt: null }))
          .eligible,
      ).toBe(true);
    });

    it('does not wait at all when waitHours is 0', () => {
      expect(
        decidePayoutEligibility(
          input({ payoutDetailsChangedAt: NOW, waitHours: 0 }),
        ).eligible,
      ).toBe(true);
    });

    it('uses the waitHours it is given', () => {
      expect(
        decidePayoutEligibility(
          input({ payoutDetailsChangedAt: changed, waitHours: 48 }),
        ).reasons,
      ).toEqual(['WAIT_NOT_OVER']);
    });
  });

  describe('BELOW_MINIMUM', () => {
    it('is eligible exactly at the minimum', () => {
      expect(
        decidePayoutEligibility(
          input({ balancePaise: 50_000, minimumPaise: 50_000 }),
        ).eligible,
      ).toBe(true);
    });

    it('is below by one paisa', () => {
      expect(
        decidePayoutEligibility(
          input({ balancePaise: 49_999, minimumPaise: 50_000 }),
        ),
      ).toEqual({ eligible: false, reasons: ['BELOW_MINIMUM'] });
    });

    it('uses the minimum it is given', () => {
      expect(
        decidePayoutEligibility(
          input({ balancePaise: 60_000, minimumPaise: 100_000 }),
        ).reasons,
      ).toEqual(['BELOW_MINIMUM']);
    });
  });

  describe('NOTHING_TO_PAY', () => {
    it('is not payable with a zero balance even when the minimum is 0', () => {
      expect(
        decidePayoutEligibility(input({ balancePaise: 0, minimumPaise: 0 })),
      ).toEqual({ eligible: false, reasons: ['NOTHING_TO_PAY'] });
    });

    it('is payable with one paisa when the minimum is 0', () => {
      expect(
        decidePayoutEligibility(input({ balancePaise: 1, minimumPaise: 0 })),
      ).toEqual({ eligible: true, reasons: [] });
    });

    it('is listed alongside BELOW_MINIMUM when there is a minimum', () => {
      expect(
        decidePayoutEligibility(
          input({ balancePaise: 0, minimumPaise: 50_000 }),
        ).reasons,
      ).toEqual(['NOTHING_TO_PAY', 'BELOW_MINIMUM']);
    });

    it('does not apply to a positive balance below the minimum', () => {
      expect(
        decidePayoutEligibility(
          input({ balancePaise: 1, minimumPaise: 50_000 }),
        ).reasons,
      ).toEqual(['BELOW_MINIMUM']);
    });
  });

  it('PAYOUT_EXISTS', () => {
    expect(
      decidePayoutEligibility(input({ hasPayoutForPeriod: true })),
    ).toEqual({
      eligible: false,
      reasons: ['PAYOUT_EXISTS'],
    });
  });

  describe('combinations list every failing reason in a fixed order', () => {
    it('two reasons', () => {
      expect(
        decidePayoutEligibility(
          input({ panVerified: false, balancePaise: 1_000 }),
        ).reasons,
      ).toEqual(['PAN_NOT_VERIFIED', 'BELOW_MINIMUM']);
    });

    it('a zero balance with a minimum gives both NOTHING_TO_PAY and BELOW_MINIMUM', () => {
      expect(
        decidePayoutEligibility(input({ panVerified: false, balancePaise: 0 }))
          .reasons,
      ).toEqual(['PAN_NOT_VERIFIED', 'NOTHING_TO_PAY', 'BELOW_MINIMUM']);
    });

    it('three reasons', () => {
      expect(
        decidePayoutEligibility(
          input({
            payoutDetailsVerified: false,
            payoutDetailsChangedAt: NOW,
            hasPayoutForPeriod: true,
          }),
        ).reasons,
      ).toEqual(['DETAILS_NOT_VERIFIED', 'WAIT_NOT_OVER', 'PAYOUT_EXISTS']);
    });

    it('all seven reasons', () => {
      expect(
        decidePayoutEligibility(
          input({
            agentStatus: 'SUSPENDED',
            panVerified: false,
            payoutDetailsVerified: false,
            payoutDetailsChangedAt: NOW,
            balancePaise: 0,
            hasPayoutForPeriod: true,
          }),
        ),
      ).toEqual({
        eligible: false,
        reasons: [
          'AGENT_NOT_PAYABLE',
          'PAN_NOT_VERIFIED',
          'DETAILS_NOT_VERIFIED',
          'WAIT_NOT_OVER',
          'NOTHING_TO_PAY',
          'BELOW_MINIMUM',
          'PAYOUT_EXISTS',
        ],
      });
    });
  });

  describe('validation', () => {
    const numeric = ['waitHours', 'balancePaise', 'minimumPaise'] as const;
    for (const field of numeric) {
      it.each([-1, 1.5, NaN, Infinity])(`rejects ${field} = %p`, (value) => {
        expect(() =>
          decidePayoutEligibility(input({ [field]: value })),
        ).toThrow(RangeError);
      });
    }

    it('rejects an invalid now', () => {
      expect(() =>
        decidePayoutEligibility(input({ now: new Date('nope') })),
      ).toThrow(RangeError);
    });

    it('rejects an invalid payoutDetailsChangedAt', () => {
      expect(() =>
        decidePayoutEligibility(
          input({ payoutDetailsChangedAt: new Date('nope') }),
        ),
      ).toThrow(RangeError);
    });
  });
});
