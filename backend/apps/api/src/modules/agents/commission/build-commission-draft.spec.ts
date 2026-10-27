import {
  buildCommissionDraft,
  CommissionDraftInput,
} from './build-commission-draft';
import { CommissionRule } from './calculate-commission';

const NOW = new Date('2026-10-27T10:00:00.000Z');
const RULE: CommissionRule = { calcType: 'PERCENTAGE', value: 1000 };

const input = (
  overrides: Partial<CommissionDraftInput> = {},
): CommissionDraftInput => ({
  rule: RULE,
  holdDays: 14,
  now: NOW,
  amountPaidPaise: 118_000,
  basePaise: 100_000,
  paidBy: 'MEMBER',
  paymentSourceReused: false,
  memberPhoneMatchesAgent: false,
  ...overrides,
});

describe('buildCommissionDraft', () => {
  describe('a clean payment', () => {
    it('is ON_HOLD with the amount, the hold date and the rule snapshot', () => {
      expect(buildCommissionDraft(input())).toEqual({
        status: 'ON_HOLD',
        holdUntil: new Date('2026-11-10T10:00:00.000Z'),
        amountPaise: 10_000,
        calcType: 'PERCENTAGE',
        value: 1000,
        reasons: [],
      });
    });

    it('calculates on the base, capped at the amount paid', () => {
      expect(
        buildCommissionDraft(
          input({ basePaise: 100_000, amountPaidPaise: 5_000 }),
        ).amountPaise,
      ).toBe(5_000);
    });

    it('ADMIN_RECORDED payments are not flagged', () => {
      expect(
        buildCommissionDraft(input({ paidBy: 'ADMIN_RECORDED' })),
      ).toMatchObject({ status: 'ON_HOLD', reasons: [] });
    });
  });

  describe('flags put the commission IN_REVIEW', () => {
    it('PAID_BY_AGENT', () => {
      expect(buildCommissionDraft(input({ paidBy: 'AGENT' }))).toMatchObject({
        status: 'IN_REVIEW',
        reasons: ['PAID_BY_AGENT'],
      });
    });

    it('PAYMENT_SOURCE_REUSED', () => {
      expect(
        buildCommissionDraft(input({ paymentSourceReused: true })),
      ).toMatchObject({
        status: 'IN_REVIEW',
        reasons: ['PAYMENT_SOURCE_REUSED'],
      });
    });

    it('SELF_MATCH', () => {
      expect(
        buildCommissionDraft(input({ memberPhoneMatchesAgent: true })),
      ).toMatchObject({ status: 'IN_REVIEW', reasons: ['SELF_MATCH'] });
    });

    it('lists two reasons in a fixed order', () => {
      expect(
        buildCommissionDraft(
          input({ memberPhoneMatchesAgent: true, paidBy: 'AGENT' }),
        ).reasons,
      ).toEqual(['PAID_BY_AGENT', 'SELF_MATCH']);
    });

    it('lists all three reasons', () => {
      expect(
        buildCommissionDraft(
          input({
            paidBy: 'AGENT',
            paymentSourceReused: true,
            memberPhoneMatchesAgent: true,
          }),
        ),
      ).toMatchObject({
        status: 'IN_REVIEW',
        reasons: ['PAID_BY_AGENT', 'PAYMENT_SOURCE_REUSED', 'SELF_MATCH'],
      });
    });

    it('still calculates the amount and the hold date when flagged', () => {
      const draft = buildCommissionDraft(input({ paidBy: 'AGENT' }));
      expect(draft.amountPaise).toBe(10_000);
      expect(draft.holdUntil).toEqual(new Date('2026-11-10T10:00:00.000Z'));
    });
  });

  describe('no commission base configured', () => {
    it('gives a null amount and still a status and hold date', () => {
      expect(buildCommissionDraft(input({ basePaise: null }))).toEqual({
        status: 'ON_HOLD',
        holdUntil: new Date('2026-11-10T10:00:00.000Z'),
        amountPaise: null,
        calcType: 'PERCENTAGE',
        value: 1000,
        reasons: [],
      });
    });

    it('keeps the flags with a null amount', () => {
      expect(
        buildCommissionDraft(
          input({ basePaise: null, paymentSourceReused: true }),
        ),
      ).toMatchObject({
        status: 'IN_REVIEW',
        amountPaise: null,
        reasons: ['PAYMENT_SOURCE_REUSED'],
      });
    });

    it('still rejects an unsupported rule', () => {
      const rule = { calcType: 'FIXED', value: 5 } as unknown as CommissionRule;
      expect(() =>
        buildCommissionDraft(input({ rule, basePaise: null })),
      ).toThrow(/Unsupported commission calcType/);
    });
  });

  describe('hold dates', () => {
    it('adds holdDays whole days to now', () => {
      expect(buildCommissionDraft(input({ holdDays: 7 })).holdUntil).toEqual(
        new Date('2026-11-03T10:00:00.000Z'),
      );
    });

    it('is now when holdDays is 0', () => {
      expect(buildCommissionDraft(input({ holdDays: 0 })).holdUntil).toEqual(
        NOW,
      );
    });

    it('does not alias or mutate now', () => {
      const draft = buildCommissionDraft(input({ holdDays: 0 }));
      expect(draft.holdUntil).not.toBe(NOW);
      expect(NOW.toISOString()).toBe('2026-10-27T10:00:00.000Z');
    });
  });

  describe('validation', () => {
    it.each([-1, 1.5, NaN, Infinity])('rejects holdDays %p', (holdDays) => {
      expect(() => buildCommissionDraft(input({ holdDays }))).toThrow(
        RangeError,
      );
    });

    it('rejects an invalid now', () => {
      expect(() =>
        buildCommissionDraft(input({ now: new Date('nope') })),
      ).toThrow(RangeError);
    });

    it.each([-1, 1.5, NaN])('rejects amountPaidPaise %p', (amountPaidPaise) => {
      expect(() => buildCommissionDraft(input({ amountPaidPaise }))).toThrow(
        RangeError,
      );
      expect(() =>
        buildCommissionDraft(input({ amountPaidPaise, basePaise: null })),
      ).toThrow(RangeError);
    });

    it.each([-1, 1.5, NaN])('rejects basePaise %p', (basePaise) => {
      expect(() => buildCommissionDraft(input({ basePaise }))).toThrow(
        RangeError,
      );
    });

    it('rejects an unsupported calcType', () => {
      const rule = { calcType: 'FIXED', value: 5 } as unknown as CommissionRule;
      expect(() => buildCommissionDraft(input({ rule }))).toThrow(
        /Unsupported commission calcType/,
      );
    });

    it.each([-1, 1.5])('rejects rule value %p', (value) => {
      expect(() =>
        buildCommissionDraft(
          input({ rule: { calcType: 'PERCENTAGE', value } }),
        ),
      ).toThrow(RangeError);
    });
  });
});
