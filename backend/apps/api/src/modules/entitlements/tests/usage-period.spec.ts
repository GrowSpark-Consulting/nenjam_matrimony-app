import { usagePeriodFor } from '../domain/usage-period';

// IST is UTC+05:30, so IST midnight is 18:30 UTC the previous day.
describe('usagePeriodFor', () => {
  it('rolls the day over at IST midnight, not UTC midnight', () => {
    const lastSecond = usagePeriodFor(
      'DAY',
      new Date('2026-10-27T18:29:59.999Z'),
      null,
    );
    const firstSecond = usagePeriodFor(
      'DAY',
      new Date('2026-10-27T18:30:00.000Z'),
      null,
    );
    expect(lastSecond.key).toBe('D:2026-10-27');
    expect(firstSecond.key).toBe('D:2026-10-28');
    expect(lastSecond.endsAt).toEqual(new Date('2026-10-27T18:30:00.000Z'));
  });

  it('keys a whole IST calendar month together and resets on the 1st', () => {
    const start = usagePeriodFor(
      'MONTH',
      new Date('2026-09-30T18:30:00.000Z'),
      null,
    );
    const end = usagePeriodFor(
      'MONTH',
      new Date('2026-10-31T18:29:59.000Z'),
      null,
    );
    expect(start.key).toBe('M:2026-10');
    expect(end.key).toBe('M:2026-10');
    expect(end.endsAt).toEqual(new Date('2026-10-31T18:30:00.000Z'));
  });

  it('rolls December into January of the next year', () => {
    const period = usagePeriodFor(
      'MONTH',
      new Date('2026-12-15T00:00:00.000Z'),
      null,
    );
    expect(period.key).toBe('M:2026-12');
    expect(period.endsAt).toEqual(new Date('2026-12-31T18:30:00.000Z'));
  });

  it('gives each subscription its own pool that resets when it ends', () => {
    const endDate = new Date('2027-01-25T00:00:00.000Z');
    expect(
      usagePeriodFor('SUBSCRIPTION', new Date(), { id: 'sub-1', endDate }),
    ).toEqual({ key: 'S:sub-1', endsAt: endDate });
  });

  it('gives a member without a subscription one lifetime free pool', () => {
    expect(usagePeriodFor('SUBSCRIPTION', new Date(), null)).toEqual({
      key: 'S:free',
      endsAt: null,
    });
  });
});
