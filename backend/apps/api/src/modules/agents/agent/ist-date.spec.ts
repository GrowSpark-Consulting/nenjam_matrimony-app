import { toIstDate } from './ist-date';

describe('toIstDate', () => {
  it('is the Indian calendar date', () => {
    expect(toIstDate(new Date('2026-10-28T10:00:00.000Z'))).toBe('2026-10-28');
  });

  it('rolls over at 18:30 UTC (midnight in India)', () => {
    expect(toIstDate(new Date('2026-10-28T18:29:59.999Z'))).toBe('2026-10-28');
    expect(toIstDate(new Date('2026-10-28T18:30:00.000Z'))).toBe('2026-10-29');
  });

  it('crosses a year end', () => {
    expect(toIstDate(new Date('2026-12-31T20:00:00.000Z'))).toBe('2027-01-01');
  });

  it.each([new Date('nope'), 'x' as unknown as Date, null as unknown as Date])(
    'refuses %p',
    (value) => {
      expect(() => toIstDate(value)).toThrow(RangeError);
    },
  );
});
