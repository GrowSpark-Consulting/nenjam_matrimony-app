-- Repair the date of birth of members whose row was written by an IST server.
--
-- BEFORE APPLYING, run the read-only impact report:
--   psql "$DATABASE_URL" -f backend/scripts/dob-normalization-impact.sql
-- It classifies every non-midnight row and prints the statements that undo
-- this migration. Save that output.
--
-- ## What is wrong, and for whom
--
-- `user_profiles.dob` and `astrology_profiles.birth_date` are TIMESTAMP(3)
-- columns holding a value that has no time of day: a birthdate. Until this
-- change the write was `new Date(dob)` over a string the client sent as
-- `1998-08-15T00:00:00.000` — no zone designator, which Node parses as LOCAL
-- midnight of whatever timezone the API server process ran in. On an IST
-- server (UTC+5:30) that stores local midnight as 18:30 on the PREVIOUS day,
-- so the row reads back one day early everywhere: the profile screen, the
-- Discover card, the age filters.
--
-- The write now goes through parseBirthDate(), which reads the calendar date
-- as written and returns UTC midnight. This migration brings the rows written
-- before that into line.
--
-- ## Only 18:30:00. This is the important part.
--
-- A non-midnight time of day is NOT by itself evidence of a timezone artifact,
-- and an earlier draft of this migration wrongly assumed it was. Inspecting
-- the real data (74 profiles) found twenty non-midnight rows in two distinct
-- populations:
--
--   18:30:00 exactly            5 rows   IST artifacts        <- repaired here
--   09:27:54.665, 15:56:09.515,
--   and 13 more sub-second      15 rows  generated timestamps <- LEFT ALONE
--
-- The second group are not timezone artifacts. Each of those rows has a `dob`
-- whose month and day equal the row's own `created_at` date (dob
-- `2001-07-22 09:27:54`, row created `2026-07-22`), and the times increment by
-- about a second per row. That is `new Date()` — "now" — with only the year
-- varied: demo profiles generated as "today, N years ago". The time component
-- is a creation timestamp, not an offset.
--
-- Rounding those to the nearest midnight would have moved five of them
-- (the 15:56:09.5xx group) forward a calendar day — `2000-07-21` to
-- `2000-07-22` — changing member data on the strength of an inference that
-- does not hold for them. A fabricated date rounded is still fabricated, just
-- differently. What to do about those fifteen rows is a product decision, not
-- a timezone repair, so this migration does not touch them.
--
-- A timezone offset can never produce a non-zero seconds component. That is
-- the discriminator, and the guard below enforces it.
--
-- ## Why the type is NOT changed
--
-- The columns stay TIMESTAMP. Every reader of them — the feed's age mapper,
-- the partner-preference age window, the compatibility scorer, the weekly
-- digest — computes with local-time getters against a timestamp, and
-- converting to DATE would shift each of those by a day on any server not
-- running UTC. That is a larger change with its own audit.
--
-- ## Safety
--
-- * Exact predicate, no rounding heuristic. `dob::time = '18:30:00'` matches
--   the IST population and nothing else; the new value is stated directly as
--   "the next day at midnight" rather than inferred by arithmetic.
-- * Idempotent. A repaired row lands at 00:00:00 and no longer matches the
--   predicate; a second run changes nothing.
-- * Measured blast radius, from the live impact report: 5 rows in
--   `user_profiles`, 0 in `astrology_profiles` (all five of its rows are
--   already at exact midnight). 54 rows already correct and the 15 generated
--   rows are all untouched.
-- * `user_profiles.dob` and `astrology_profiles.birth_date` are written from
--   the same parsed value in the same call (ProfileService.writeProfileFromDraft),
--   so the same predicate and the same shift apply to both and they stay
--   consistent. Section 4 of the impact report asserts that both ways.
-- * No column is added, dropped, renamed, retyped or made nullable. No row is
--   deleted. No row outside the predicate is read for update.
-- * NOT self-reversing. Section 3 of the impact report prints the exact undo
--   statements; Neon branching / PITR is the better primary rollback.
--
-- ## The guard
--
-- The narrow predicate introduces a new failure mode: a genuine timezone
-- artifact written at some OTHER offset (05:00:00 for UTC-5, 19:00:00 for
-- UTC+5, ...) would be silently left broken. So rather than assume 18:30 is
-- the only offset in the data, this aborts if any row carries a time of day
-- shaped like a UTC offset — zero seconds, and minutes on a quarter hour,
-- which is every real-world offset — that is not 18:30:00. Widening the
-- predicate must then be a deliberate act, not an omission. Prisma runs a
-- migration file in a transaction, so a raised exception rolls back cleanly.
DO $$
DECLARE
  other_offset_rows integer;
BEGIN
  SELECT
    (SELECT count(*) FROM "user_profiles"
      WHERE "dob"::time <> '00:00:00'
        AND "dob"::time <> '18:30:00'
        AND EXTRACT(SECOND FROM "dob"::time) = 0
        AND EXTRACT(MINUTE FROM "dob"::time)::int IN (0, 15, 30, 45))
  + (SELECT count(*) FROM "astrology_profiles"
      WHERE "birth_date"::time <> '00:00:00'
        AND "birth_date"::time <> '18:30:00'
        AND EXTRACT(SECOND FROM "birth_date"::time) = 0
        AND EXTRACT(MINUTE FROM "birth_date"::time)::int IN (0, 15, 30, 45))
  INTO other_offset_rows;

  IF other_offset_rows > 0 THEN
    RAISE EXCEPTION
      'Refusing to normalise dob: % row(s) carry a time of day shaped like a '
      'UTC offset other than 18:30:00, so this migration would leave them '
      'broken. Run backend/scripts/dob-normalization-impact.sql, confirm which '
      'offsets are present, and widen the predicate deliberately.',
      other_offset_rows;
  END IF;
END
$$;

-- 18:30:00 is local midnight of the FOLLOWING day at UTC+05:30, so the
-- intended calendar date is stated directly rather than rounded into.
UPDATE "user_profiles"
SET "dob" = date_trunc('day', "dob") + interval '1 day'
WHERE "dob"::time = '18:30:00';

UPDATE "astrology_profiles"
SET "birth_date" = date_trunc('day', "birth_date") + interval '1 day'
WHERE "birth_date"::time = '18:30:00';
