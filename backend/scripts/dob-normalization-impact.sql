-- Read-only impact report for migration 20260908120000_normalize_dob_to_utc_midnight.
--
--   psql "$DATABASE_URL" -f backend/scripts/dob-normalization-impact.sql
--
-- SELECTs only. Nothing here writes, locks or changes anything, so it is safe
-- to run against production. Run it BEFORE the migration and keep the output:
-- section 5 is the rollback script.
--
-- On a pooled connection (Neon), enforce read-only at session level rather
-- than with `options=` on the URL, which the pooler rejects:
--   psql "$URL" -c "SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY;" \
--                -f backend/scripts/dob-normalization-impact.sql
--
-- ## What this is looking for
--
-- `user_profiles.dob` and `astrology_profiles.birth_date` are TIMESTAMP(3)
-- columns holding a value with no time of day. Until the birthdate change the
-- write was `new Date(dob)` over a zone-less string, which Node parses as
-- LOCAL midnight of the API server's timezone — so on an IST server the row
-- was stored at 18:30 on the previous day and reads back one day early.
--
-- A non-midnight time is NOT automatically that bug, and an earlier version of
-- this report assumed it was. Real data holds at least two populations:
--
--   * TIMEZONE ARTIFACT   - a constant offset from midnight, so zero seconds
--                           and minutes on a quarter hour (18:30:00, 05:00:00).
--                           Repairable: the offset is known and undoable.
--   * GENERATED TIMESTAMP - an arbitrary wall-clock time with non-zero seconds
--                           or milliseconds (09:27:54.665), i.e. `new Date()`
--                           captured at row creation, with only the year
--                           varied. NOT repairable by timezone reasoning, and
--                           rounding it would move a member's date on a false
--                           premise.
--
-- A timezone offset can never produce a non-zero seconds component. That is
-- the discriminator used throughout, and section 3 is the guard that stops the
-- migration acting on anything it cannot justify.

\echo ''
\echo '=== 1. Is the migration necessary? ==================================='
\echo 'repairable_rows is what the migration would actually change.'
\echo 'Zero means it is a documented no-op.'
\echo ''

SELECT
  'user_profiles.dob'                                       AS column_name,
  count(*)                                                  AS total_rows,
  count(*) FILTER (WHERE dob::time = '00:00:00')            AS already_correct,
  count(*) FILTER (WHERE dob::time = '18:30:00')            AS repairable_rows,
  count(*) FILTER (
    WHERE dob::time <> '00:00:00'
      AND EXTRACT(SECOND FROM dob::time) <> 0
  )                                                         AS generated_left_alone
FROM user_profiles
UNION ALL
SELECT
  'astrology_profiles.birth_date',
  count(*),
  count(*) FILTER (WHERE birth_date::time = '00:00:00'),
  count(*) FILTER (WHERE birth_date::time = '18:30:00'),
  count(*) FILTER (
    WHERE birth_date::time <> '00:00:00'
      AND EXTRACT(SECOND FROM birth_date::time) <> 0
  )
FROM astrology_profiles;

\echo ''
\echo '=== 2. Every non-midnight value, classified ========================='
\echo 'TIMEZONE ARTIFACT   -> a real offset; the migration repairs 18:30:00.'
\echo 'GENERATED TIMESTAMP -> new Date() at row creation; LEFT UNTOUCHED.'
\echo ''

SELECT
  time_of_day,
  rows,
  classification,
  CASE
    WHEN classification = 'TIMEZONE ARTIFACT' AND time_of_day = '18:30:00'
      THEN 'REPAIRED -> next calendar day'
    WHEN classification = 'TIMEZONE ARTIFACT'
      THEN 'NOT REPAIRED - offset not covered (the migration will abort)'
    ELSE 'UNTOUCHED - not a timezone artifact'
  END AS action
FROM (
  SELECT
    dob::time AS time_of_day,
    count(*)  AS rows,
    CASE
      WHEN EXTRACT(SECOND FROM dob::time) = 0
       AND EXTRACT(MINUTE FROM dob::time)::int IN (0, 15, 30, 45)
        THEN 'TIMEZONE ARTIFACT'
      ELSE 'GENERATED TIMESTAMP'
    END AS classification
  FROM user_profiles
  WHERE dob::time <> '00:00:00'
  GROUP BY 1, 3
) t
ORDER BY classification, rows DESC;

\echo ''
\echo '=== 2b. Corroboration: do the generated rows match their created_at? ='
\echo 'same_day_of_year = t means the value is the row creation instant with'
\echo 'the year shifted - conclusive evidence it is not a timezone artifact'
\echo 'and must not be rounded.'
\echo ''

SELECT
  left(p.user_id, 8)                                       AS user_prefix,
  p.dob,
  to_char(p.dob, 'MM-DD')                                  AS dob_month_day,
  to_char(p.created_at, 'MM-DD')                           AS created_month_day,
  to_char(p.dob, 'MM-DD') = to_char(p.created_at, 'MM-DD') AS same_day_of_year
FROM user_profiles p
WHERE p.dob::time <> '00:00:00'
  AND EXTRACT(SECOND FROM p.dob::time) <> 0
ORDER BY p.dob::time
LIMIT 50;

\echo ''
\echo '=== 3. GUARD - MUST return zero rows ================================'
\echo 'A time of day shaped like a UTC offset (zero seconds, minutes on a'
\echo 'quarter hour) that is NOT 18:30:00 is a timezone artifact the narrowed'
\echo 'migration would silently leave broken. The migration RAISES and aborts'
\echo 'if any exist, so widening it stays a deliberate act rather than an'
\echo 'omission.'
\echo ''

SELECT 'user_profiles.dob' AS column_name, user_id, dob, dob::time AS time_of_day
FROM user_profiles
WHERE dob::time NOT IN ('00:00:00', '18:30:00')
  AND EXTRACT(SECOND FROM dob::time) = 0
  AND EXTRACT(MINUTE FROM dob::time)::int IN (0, 15, 30, 45)
UNION ALL
SELECT 'astrology_profiles.birth_date', user_id, birth_date, birth_date::time
FROM astrology_profiles
WHERE birth_date::time NOT IN ('00:00:00', '18:30:00')
  AND EXTRACT(SECOND FROM birth_date::time) = 0
  AND EXTRACT(MINUTE FROM birth_date::time)::int IN (0, 15, 30, 45);

\echo ''
\echo '=== 4. Exactly which calendar dates would change ===================='
\echo 'Only 18:30:00 rows appear here. Each moves forward one day, back to the'
\echo 'date the member actually entered before IST shifted it.'
\echo ''

SELECT
  user_id,
  dob                                               AS stored_now,
  dob::date                                         AS reads_as_now,
  date_trunc('day', dob) + interval '1 day'         AS stored_after,
  (date_trunc('day', dob) + interval '1 day')::date AS reads_as_after
FROM user_profiles
WHERE dob::time = '18:30:00'
ORDER BY user_id;

\echo ''
\echo '=== 5. Rollback reference - SAVE THIS OUTPUT ========================'
\echo 'The UPDATE is not self-reversing. These statements put every repaired'
\echo 'row back exactly as it was. (Neon branch / PITR is the better primary'
\echo 'rollback; this is the surgical one.)'
\echo ''

SELECT format(
  'UPDATE user_profiles SET dob = %L WHERE user_id = %L;', dob, user_id
) AS undo_statement
FROM user_profiles
WHERE dob::time = '18:30:00'
UNION ALL
SELECT format(
  'UPDATE astrology_profiles SET birth_date = %L WHERE user_id = %L;',
  birth_date, user_id
)
FROM astrology_profiles
WHERE birth_date::time = '18:30:00';

\echo ''
\echo '=== 6. Do the two columns agree, before and after? =================='
\echo 'astrology_profiles.birth_date is the same fact as user_profiles.dob,'
\echo 'written from the same parsed value in the same call. Both lists MUST be'
\echo 'empty: any disagreement predates this migration and is a separate bug.'
\echo ''

SELECT
  p.user_id,
  p.dob             AS profile_dob,
  a.birth_date      AS astrology_birth_date,
  'disagree BEFORE' AS when_
FROM user_profiles p
JOIN astrology_profiles a ON a.user_id = p.user_id
WHERE p.dob <> a.birth_date
UNION ALL
SELECT
  p.user_id,
  CASE WHEN p.dob::time = '18:30:00'
       THEN date_trunc('day', p.dob) + interval '1 day' ELSE p.dob END,
  CASE WHEN a.birth_date::time = '18:30:00'
       THEN date_trunc('day', a.birth_date) + interval '1 day'
       ELSE a.birth_date END,
  'disagree AFTER'
FROM user_profiles p
JOIN astrology_profiles a ON a.user_id = p.user_id
WHERE (CASE WHEN p.dob::time = '18:30:00'
            THEN date_trunc('day', p.dob) + interval '1 day' ELSE p.dob END)
   <> (CASE WHEN a.birth_date::time = '18:30:00'
            THEN date_trunc('day', a.birth_date) + interval '1 day'
            ELSE a.birth_date END);

\echo ''
\echo '=== Done. Nothing was modified. ====================================='
\echo ''
