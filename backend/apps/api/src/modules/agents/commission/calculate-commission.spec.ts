import { calculateCommission, CommissionRule } from './calculate-commission';

const pct = (value: number): CommissionRule => ({
  calcType: 'PERCENTAGE',
  value,
});

describe('calculateCommission', () => {
  it('takes basis points of the base (10% of Rs. 999.00)', () => {
    expect(calculateCommission(pct(1000), 99_900, 99_900)).toBe(9_990);
  });

  describe('base versus amount paid', () => {
    it('computes on the base when it is lower than the amount paid (e.g. ex-GST)', () => {
      // Paid 118.00, base 100.00 -> 10% of the base, not of the amount paid.
      expect(calculateCommission(pct(1000), 10_000, 11_800)).toBe(1_000);
    });

    it('is capped at the amount paid when the base is above it', () => {
      // Base 1000.00 but only 50.00 paid; 10% of base = 100.00 > 50.00.
      expect(calculateCommission(pct(1000), 100_000, 5_000)).toBe(5_000);
    });

    it('is not capped when the base is above the amount paid but the result is below it', () => {
      expect(calculateCommission(pct(1000), 20_000, 19_000)).toBe(2_000);
    });
  });

  describe('rounding', () => {
    it('rounds down at exactly half', () => {
      // 10% of 5 paise = 0.5 -> 0
      expect(calculateCommission(pct(1000), 5, 5)).toBe(0);
    });

    it('rounds down below half', () => {
      // 10% of 4 paise = 0.4 -> 0
      expect(calculateCommission(pct(1000), 4, 4)).toBe(0);
    });

    it('rounds down above half', () => {
      // 10% of 16 paise = 1.6 -> 1
      expect(calculateCommission(pct(1000), 16, 16)).toBe(1);
    });

    it('always returns an integer', () => {
      for (const amount of [1, 7, 333, 12_345, 99_999]) {
        expect(
          Number.isInteger(calculateCommission(pct(1234), amount, amount)),
        ).toBe(true);
      }
    });
  });

  describe('zero', () => {
    it('is 0 for a zero base', () => {
      expect(calculateCommission(pct(1000), 0, 99_900)).toBe(0);
    });

    it('is 0 for a zero amount paid', () => {
      expect(calculateCommission(pct(1000), 99_900, 0)).toBe(0);
    });

    it('is 0 for a zero rate', () => {
      expect(calculateCommission(pct(0), 99_900, 99_900)).toBe(0);
    });
  });

  describe('cap', () => {
    it('pays exactly the amount paid at 100%', () => {
      expect(calculateCommission(pct(10_000), 50_000, 50_000)).toBe(50_000);
    });

    it('never exceeds the amount paid, even above 100%', () => {
      expect(calculateCommission(pct(25_000), 50_000, 50_000)).toBe(50_000);
    });
  });

  describe('unsupported type', () => {
    it('throws rather than guessing', () => {
      const rule = {
        calcType: 'FIXED',
        value: 5000,
      } as unknown as CommissionRule;
      expect(() => calculateCommission(rule, 99_900, 99_900)).toThrow(
        /Unsupported commission calcType: FIXED/,
      );
    });
  });

  describe('invalid input', () => {
    it.each([-1, 1.5, NaN, Infinity])('rejects base %p', (base) => {
      expect(() => calculateCommission(pct(1000), base, 1000)).toThrow(
        RangeError,
      );
    });

    it.each([-1, 1.5, NaN, Infinity])('rejects amount paid %p', (paid) => {
      expect(() => calculateCommission(pct(1000), 1000, paid)).toThrow(
        RangeError,
      );
    });

    it.each([-1, 10.5, NaN])('rejects value %p', (value) => {
      expect(() => calculateCommission(pct(value), 1000, 1000)).toThrow(
        RangeError,
      );
    });
  });
});
