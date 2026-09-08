import { readFileSync } from 'fs';
import { join } from 'path';

/**
 * What migration 20260908120000_normalize_dob_to_utc_midnight does, and — more
 * importantly — what it leaves alone.
 *
 * ## What this can and cannot prove
 *
 * It does not execute SQL; there is no database in this suite. It does two
 * things that together are worth more than either alone:
 *
 *  1. **Pins the migration text.** The predicate and the assignment are
 *     asserted to appear literally in `migration.sql`, and the rounding
 *     expression an earlier draft used is asserted to be gone. So the model
 *     below cannot quietly drift away from the statement that will actually
 *     run.
 *  2. **Applies that rule to the real data.** The fixtures are the twenty
 *     non-midnight rows actually present in `user_profiles`, read out of the
 *     live database read-only. They are the reason the migration was narrowed.
 *
 * ## Why it was narrowed
 *
 * The first version updated every row whose `dob` carried a time component,
 * rounding to the nearest midnight on the assumption that a time component
 * always means a timezone offset. The live data disproved that. Two
 * populations exist:
 *
 *   * `18:30:00` exactly (5 rows) — IST artifacts. Local midnight at UTC+5:30
 *     stored as 18:30 the previous day, so the row reads back a day early.
 *     These are the rows the migration repairs.
 *   * sub-second times (15 rows) — `new Date()` captured at row creation with
 *     only the year varied, which the `dob_month_day = created_month_day`
 *     assertion below demonstrates. Rounding these would have moved five of
 *     them (`15:56:09.5xx`) forward a calendar day for no valid reason.
 *
 * A timezone offset cannot produce a non-zero seconds component. That is the
 * discriminator, and these tests hold the migration to it.
 */

const MIGRATION_SQL = readFileSync(
  join(
    __dirname,
    '../../../../../../libs/database/prisma/migrations',
    '20260908120000_normalize_dob_to_utc_midnight/migration.sql',
  ),
  'utf8',
);

// ─── A model of the migration's two statements ──────────────────────
//
// Mirrors, exactly:
//   UPDATE ... SET dob = date_trunc('day', dob) + interval '1 day'
//   WHERE dob::time = '18:30:00';

/** `YYYY-MM-DD HH:MM:SS[.mmm]`, as Postgres renders a timestamp(3). */
function parseStoredTimestamp(stored: string): {
  y: number;
  mo: number;
  d: number;
  timeOfDay: string;
} {
  const m =
    /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,3}))?$/.exec(
      stored,
    );
  if (!m) throw new Error(`unparseable fixture: ${stored}`);
  const [, y, mo, d, hh, mi, ss, ms] = m;
  // Rendered the way Postgres prints `dob::time`: fractional seconds only when
  // non-zero, which is what makes 18:30:00 distinguishable from 18:30:00.123.
  const timeOfDay = ms ? `${hh}:${mi}:${ss}.${ms}` : `${hh}:${mi}:${ss}`;
  return { y: Number(y), mo: Number(mo), d: Number(d), timeOfDay };
}

/** `WHERE dob::time = '18:30:00'` */
function migrationWouldTouch(stored: string): boolean {
  return parseStoredTimestamp(stored).timeOfDay === '18:30:00';
}

/**
 * The value after the migration: `date_trunc('day', dob) + interval '1 day'`
 * for a matching row, and the untouched original for every other row.
 *
 * UTC arithmetic throughout, so the result does not depend on the timezone
 * this test happens to run in.
 */
function applyMigration(stored: string): string {
  if (!migrationWouldTouch(stored)) return stored;
  const { y, mo, d } = parseStoredTimestamp(stored);
  const nextDay = new Date(Date.UTC(y, mo - 1, d + 1));
  return `${nextDay.toISOString().slice(0, 10)} 00:00:00`;
}

/** The calendar date a stored value reads back as. */
const readsAs = (stored: string) => stored.slice(0, 10);

// ─── The real rows, read read-only from user_profiles ────────────────

/** The 5 IST artifacts. Each reads back one day before what was entered. */
const IST_ARTIFACTS = [
  { userId: '36cfa839', dob: '2000-12-31 18:30:00', expected: '2001-01-01' },
  { userId: 'b29a542a', dob: '2000-12-31 18:30:00', expected: '2001-01-01' },
  { userId: 'f11e5c7a', dob: '2000-12-31 18:30:00', expected: '2001-01-01' },
  { userId: '6d152521', dob: '2001-01-02 18:30:00', expected: '2001-01-03' },
  { userId: 'c67fc7c3', dob: '2003-01-08 18:30:00', expected: '2003-01-09' },
];

/**
 * The 15 generated rows. `createdMonthDay` is the row's own `created_at`
 * month-day — equal to the dob's in every case, which is what identifies the
 * value as a creation timestamp rather than a timezone artifact.
 */
const GENERATED_TIMESTAMPS = [
  {
    userId: '29f81b86',
    dob: '2001-07-22 09:27:54.665',
    createdMonthDay: '07-22',
  },
  {
    userId: 'd3824a06',
    dob: '1999-07-22 09:27:55.820',
    createdMonthDay: '07-22',
  },
  {
    userId: 'bcb4affc',
    dob: '2000-07-22 09:27:57.065',
    createdMonthDay: '07-22',
  },
  {
    userId: 'fddc8cb0',
    dob: '1998-07-22 09:27:58.361',
    createdMonthDay: '07-22',
  },
  {
    userId: 'def90639',
    dob: '2002-07-22 09:27:59.385',
    createdMonthDay: '07-22',
  },
  {
    userId: '004680bc',
    dob: '1997-07-22 09:28:00.751',
    createdMonthDay: '07-22',
  },
  {
    userId: '3532b8fc',
    dob: '1995-07-22 09:28:01.911',
    createdMonthDay: '07-22',
  },
  {
    userId: 'fa9444a9',
    dob: '1996-07-22 09:28:02.921',
    createdMonthDay: '07-22',
  },
  {
    userId: 'd310c10a',
    dob: '1994-07-22 09:28:04.126',
    createdMonthDay: '07-22',
  },
  {
    userId: '9a470315',
    dob: '1998-07-22 09:28:05.156',
    createdMonthDay: '07-22',
  },
  {
    userId: 'b9514cff',
    dob: '2000-07-21 15:56:09.515',
    createdMonthDay: '07-21',
  },
  {
    userId: 'd38c51b2',
    dob: '2002-07-21 15:56:09.526',
    createdMonthDay: '07-21',
  },
  {
    userId: '729edf58',
    dob: '1997-07-21 15:56:09.527',
    createdMonthDay: '07-21',
  },
  {
    userId: '11734bc1',
    dob: '1995-07-21 15:56:09.531',
    createdMonthDay: '07-21',
  },
  {
    userId: 'c1c6c3a5',
    dob: '1999-07-21 15:56:09.533',
    createdMonthDay: '07-21',
  },
];

/** Rows already correct — 54 of the 74 in `user_profiles`. */
const ALREADY_MIDNIGHT = [
  '1994-01-01 00:00:00',
  '1998-08-15 00:00:00',
  '2005-12-01 00:00:00',
  '2000-02-29 00:00:00',
];

describe('the migration statement itself', () => {
  it('targets exactly 18:30:00 and nothing else', () => {
    expect(MIGRATION_SQL).toContain(`WHERE "dob"::time = '18:30:00'`);
    expect(MIGRATION_SQL).toContain(`WHERE "birth_date"::time = '18:30:00'`);
  });

  it('states the new value directly rather than rounding into it', () => {
    expect(MIGRATION_SQL).toContain(
      `date_trunc('day', "dob") + interval '1 day'`,
    );
  });

  it('no longer rounds every non-midnight row to the nearest midnight', () => {
    // The expression that would have moved five generated rows a day forward.
    expect(MIGRATION_SQL).not.toContain(`+ interval '12 hours'`);
    expect(MIGRATION_SQL).not.toContain(`<> date_trunc('day', "dob")`);
  });

  it('keeps a guard against a timezone offset it does not cover', () => {
    expect(MIGRATION_SQL).toContain('RAISE EXCEPTION');
    expect(MIGRATION_SQL).toContain('EXTRACT(SECOND FROM');
  });

  it('changes no schema and deletes nothing', () => {
    for (const forbidden of [
      'DROP TABLE',
      'DROP COLUMN',
      'ALTER COLUMN',
      'DELETE FROM',
      'TRUNCATE',
    ]) {
      expect(MIGRATION_SQL).not.toContain(forbidden);
    }
  });
});

describe('18:30:00 rows are repaired to the next calendar date', () => {
  it.each(IST_ARTIFACTS)(
    'user $userId: $dob -> $expected',
    ({ dob, expected }) => {
      expect(migrationWouldTouch(dob)).toBe(true);
      const after = applyMigration(dob);
      expect(readsAs(after)).toBe(expected);
      // Repaired to midnight, so the value is now a clean calendar date.
      expect(after).toBe(`${expected} 00:00:00`);
      // Exactly one day forward — the IST offset undone, no more.
      const before = new Date(`${readsAs(dob)}T00:00:00.000Z`).getTime();
      const afterMs = new Date(`${readsAs(after)}T00:00:00.000Z`).getTime();
      expect(afterMs - before).toBe(24 * 60 * 60 * 1000);
    },
  );

  it('crosses a year boundary correctly', () => {
    // The case that makes the off-by-one visible: three members currently
    // read as born on 31 December 2000, having entered 1 January 2001.
    expect(readsAs(applyMigration('2000-12-31 18:30:00'))).toBe('2001-01-01');
  });

  it('crosses a leap day correctly', () => {
    expect(readsAs(applyMigration('2004-02-28 18:30:00'))).toBe('2004-02-29');
    expect(readsAs(applyMigration('2004-02-29 18:30:00'))).toBe('2004-03-01');
    // A common year has no 29 February to land on.
    expect(readsAs(applyMigration('2003-02-28 18:30:00'))).toBe('2003-03-01');
  });

  it('is idempotent — a repaired row no longer matches', () => {
    const once = applyMigration('2000-12-31 18:30:00');
    expect(migrationWouldTouch(once)).toBe(false);
    expect(applyMigration(once)).toBe(once);
  });
});

describe('generated sub-second rows are left untouched', () => {
  it.each(GENERATED_TIMESTAMPS)(
    'user $userId: $dob is not matched',
    ({ dob }) => {
      expect(migrationWouldTouch(dob)).toBe(false);
      expect(applyMigration(dob)).toBe(dob);
    },
  );

  it('the 15:56 group would have been corrupted by the old rounding', () => {
    // The concrete harm the narrowing prevents: nearest-midnight rounding
    // moved each of these forward a day, changing a member's stored date on
    // the strength of an inference that does not hold for them.
    const roundedToNearestMidnight = (stored: string) => {
      const { y, mo, d, timeOfDay } = parseStoredTimestamp(stored);
      const past = timeOfDay >= '12:00:00' ? 1 : 0;
      return new Date(Date.UTC(y, mo - 1, d + past)).toISOString().slice(0, 10);
    };

    const fifteen56 = GENERATED_TIMESTAMPS.filter((r) =>
      r.dob.includes('15:56:09'),
    );
    expect(fifteen56).toHaveLength(5);

    for (const row of fifteen56) {
      expect(roundedToNearestMidnight(row.dob)).not.toBe(readsAs(row.dob));
      // The narrowed migration leaves the date exactly where it is.
      expect(readsAs(applyMigration(row.dob))).toBe(readsAs(row.dob));
    }
  });

  it('is corroborated as a creation timestamp, not an offset', () => {
    for (const row of GENERATED_TIMESTAMPS) {
      // dob month-day equals the row's own created_at month-day.
      expect(row.dob.slice(5, 10)).toBe(row.createdMonthDay);
      // And it carries a non-zero seconds component, which no UTC offset can.
      const { timeOfDay } = parseStoredTimestamp(row.dob);
      expect(timeOfDay.slice(6)).not.toBe('00');
    }
  });
});

describe('midnight rows are left untouched', () => {
  it.each(ALREADY_MIDNIGHT)('%s is already correct', (dob) => {
    expect(migrationWouldTouch(dob)).toBe(false);
    expect(applyMigration(dob)).toBe(dob);
  });
});

describe('the measured blast radius', () => {
  it('matches what the impact report found: 5 repaired, 15 untouched', () => {
    const all = [
      ...IST_ARTIFACTS.map((r) => r.dob),
      ...GENERATED_TIMESTAMPS.map((r) => r.dob),
      ...ALREADY_MIDNIGHT,
    ];
    const touched = all.filter(migrationWouldTouch);

    expect(touched).toHaveLength(5);
    expect(all.filter((d) => !migrationWouldTouch(d))).toHaveLength(
      GENERATED_TIMESTAMPS.length + ALREADY_MIDNIGHT.length,
    );
    // Every touched row moves a date; no untouched row does.
    for (const dob of all) {
      const moved = readsAs(applyMigration(dob)) !== readsAs(dob);
      expect(moved).toBe(migrationWouldTouch(dob));
    }
  });
});
