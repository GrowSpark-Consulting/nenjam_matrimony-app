import { windowFor } from '../domain/schedule';

// The one scheduling rule, shared by activation and by the purchase options
// /membership/me shows (so the app is told exactly what will happen).
const DAY = 24 * 3600 * 1000;
const NOW = new Date('2026-10-27T00:00:00.000Z');
const at = (days: number) => new Date(NOW.getTime() + days * DAY);
const GOLD = 1;
const PLATINUM = 2;

describe('windowFor', () => {
  it('starts a first purchase now', () => {
    expect(windowFor([], GOLD, 90 * DAY, NOW)).toEqual({
      kind: 'NEW',
      startDate: NOW,
      endDate: at(90),
      scheduled: false,
    });
  });

  it('starts an upgrade now, overlapping the lower plan', () => {
    const w = windowFor(
      [{ tier: GOLD, endDate: at(60) }],
      PLATINUM,
      90 * DAY,
      NOW,
    );
    expect(w).toMatchObject({
      kind: 'UPGRADE',
      startDate: NOW,
      scheduled: false,
    });
  });

  it('queues a renewal behind the plan already held', () => {
    const w = windowFor([{ tier: GOLD, endDate: at(60) }], GOLD, 90 * DAY, NOW);
    expect(w).toEqual({
      kind: 'RENEWAL',
      startDate: at(60),
      endDate: at(150),
      scheduled: true,
    });
  });

  it('queues a downgrade behind the last same-or-higher plan, including queued ones', () => {
    const held = [
      { tier: PLATINUM, endDate: at(30) },
      { tier: GOLD, endDate: at(200) }, // Gold already queued/overlapping
    ];
    const w = windowFor(held, GOLD, 90 * DAY, NOW);
    expect(w).toMatchObject({ kind: 'DOWNGRADE', startDate: at(200) });
  });
});
