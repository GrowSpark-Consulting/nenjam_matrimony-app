import type { PayoutIneligibleReason } from './decide-payout-eligibility';
import { planPayout, PlanPayoutInput } from './plan-payout';

const ELIGIBLE = { eligible: true, reasons: [] };

const input = (overrides: Partial<PlanPayoutInput> = {}): PlanPayoutInput => ({
  agentId: 'agent-1',
  period: '2026-11',
  commissions: [
    { id: 'c1', creditedPaise: 10_000, reversedPaise: 0 },
    { id: 'c2', creditedPaise: 60_000, reversedPaise: 2_500 },
  ],
  eligibility: ELIGIBLE,
  taxWithholding: null,
  ...overrides,
});

describe('planPayout', () => {
  it('plans a payout for the net of each commission', () => {
    expect(planPayout(input())).toEqual({
      ok: true,
      payout: {
        agentId: 'agent-1',
        period: '2026-11',
        amountPaise: 67_500,
        taxWithheldPaise: 0,
        netPaise: 67_500,
        commissionIds: ['c1', 'c2'],
        warnings: ['TAX_RULE_NOT_SET'],
      },
    });
  });

  it('includes a fully reversed commission at zero', () => {
    const result = planPayout(
      input({
        commissions: [
          { id: 'c1', creditedPaise: 10_000, reversedPaise: 10_000 },
          { id: 'c2', creditedPaise: 5_000, reversedPaise: 0 },
        ],
      }),
    );
    expect(result).toMatchObject({
      ok: true,
      payout: { amountPaise: 5_000, commissionIds: ['c1', 'c2'] },
    });
  });

  describe('eligibility', () => {
    it('returns the same reasons when not eligible', () => {
      const eligibility: PlanPayoutInput['eligibility'] = {
        eligible: false,
        reasons: ['PAN_NOT_VERIFIED', 'BELOW_MINIMUM'],
      };
      expect(planPayout(input({ eligibility }))).toEqual({
        ok: false,
        reasons: ['PAN_NOT_VERIFIED', 'BELOW_MINIMUM'],
      });
    });

    it('returns a copy, not the caller array', () => {
      const reasons: PayoutIneligibleReason[] = ['AGENT_NOT_PAYABLE'];
      const result = planPayout(
        input({ eligibility: { eligible: false, reasons } }),
      );
      expect(result.ok === false && result.reasons).not.toBe(reasons);
    });

    it('beats NOTHING_TO_PAY and TAX_RULE_UNSUPPORTED', () => {
      expect(
        planPayout(
          input({
            eligibility: { eligible: false, reasons: ['PAYOUT_EXISTS'] },
            commissions: [],
            taxWithholding: { rate: 1000 },
          }),
        ),
      ).toEqual({ ok: false, reasons: ['PAYOUT_EXISTS'] });
    });
  });

  describe('tax withholding', () => {
    it.each([null, undefined])(
      '%p means 0 withheld with a TAX_RULE_NOT_SET warning',
      (taxWithholding) => {
        expect(planPayout(input({ taxWithholding }))).toMatchObject({
          ok: true,
          payout: {
            taxWithheldPaise: 0,
            netPaise: 67_500,
            warnings: ['TAX_RULE_NOT_SET'],
          },
        });
      },
    );

    it.each([{ rate: 1000 }, 0, false, '', 'TDS_194H', [1]])(
      'any set value (%p) is TAX_RULE_UNSUPPORTED',
      (taxWithholding) => {
        expect(planPayout(input({ taxWithholding }))).toEqual({
          ok: false,
          reasons: ['TAX_RULE_UNSUPPORTED'],
        });
      },
    );
  });

  describe('NOTHING_TO_PAY', () => {
    it('for an empty commission list', () => {
      expect(planPayout(input({ commissions: [] }))).toEqual({
        ok: false,
        reasons: ['NOTHING_TO_PAY'],
      });
    });

    it('when every commission was fully reversed', () => {
      expect(
        planPayout(
          input({
            commissions: [
              { id: 'c1', creditedPaise: 5_000, reversedPaise: 5_000 },
            ],
          }),
        ),
      ).toEqual({ ok: false, reasons: ['NOTHING_TO_PAY'] });
    });

    it('is listed together with TAX_RULE_UNSUPPORTED', () => {
      expect(
        planPayout(input({ commissions: [], taxWithholding: { rate: 1 } })),
      ).toEqual({
        ok: false,
        reasons: ['NOTHING_TO_PAY', 'TAX_RULE_UNSUPPORTED'],
      });
    });
  });

  describe('validation', () => {
    it.each([
      '2026-1',
      '2026-13',
      '2026-00',
      '26-11',
      '2026/11',
      '2026-11-01',
      '',
    ])('rejects period %p', (period) => {
      expect(() => planPayout(input({ period }))).toThrow(RangeError);
    });

    it.each(['2026-01', '2026-09', '2026-10', '2026-12'])(
      'accepts period %p',
      (period) => {
        expect(planPayout(input({ period })).ok).toBe(true);
      },
    );

    it('rejects an empty agentId', () => {
      expect(() => planPayout(input({ agentId: '' }))).toThrow(RangeError);
    });

    it('rejects a commission with more reversed than credited', () => {
      expect(() =>
        planPayout(
          input({
            commissions: [{ id: 'c1', creditedPaise: 100, reversedPaise: 101 }],
          }),
        ),
      ).toThrow(RangeError);
    });

    it.each([-1, 1.5, NaN, Infinity])('rejects creditedPaise %p', (value) => {
      expect(() =>
        planPayout(
          input({
            commissions: [{ id: 'c1', creditedPaise: value, reversedPaise: 0 }],
          }),
        ),
      ).toThrow(RangeError);
    });

    it.each([-1, 1.5, NaN])('rejects reversedPaise %p', (value) => {
      expect(() =>
        planPayout(
          input({
            commissions: [
              { id: 'c1', creditedPaise: 100, reversedPaise: value },
            ],
          }),
        ),
      ).toThrow(RangeError);
    });

    it('rejects a commission listed twice', () => {
      expect(() =>
        planPayout(
          input({
            commissions: [
              { id: 'c1', creditedPaise: 100, reversedPaise: 0 },
              { id: 'c1', creditedPaise: 100, reversedPaise: 0 },
            ],
          }),
        ),
      ).toThrow(/listed twice/);
    });

    it('rejects a commission with no id', () => {
      expect(() =>
        planPayout(
          input({
            commissions: [{ id: '', creditedPaise: 100, reversedPaise: 0 }],
          }),
        ),
      ).toThrow(RangeError);
    });

    it('validates even when the agent is not eligible', () => {
      expect(() =>
        planPayout(
          input({
            period: 'bad',
            eligibility: { eligible: false, reasons: ['PAN_NOT_VERIFIED'] },
          }),
        ),
      ).toThrow(RangeError);
    });

    it('rejects a total outside the safe integer range', () => {
      expect(() =>
        planPayout(
          input({
            commissions: [
              {
                id: 'c1',
                creditedPaise: Number.MAX_SAFE_INTEGER,
                reversedPaise: 0,
              },
              { id: 'c2', creditedPaise: 1, reversedPaise: 0 },
            ],
          }),
        ),
      ).toThrow(RangeError);
    });
  });
});
