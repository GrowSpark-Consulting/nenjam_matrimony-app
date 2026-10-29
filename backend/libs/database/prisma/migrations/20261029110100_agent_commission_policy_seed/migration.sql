-- Commission policy version 1 (Raja, 28 Oct): 10% (1000 basis points) of the
-- commission base, a 14-day hold. A policy row, not a constant: changing the
-- rule later means adding version 2, never editing this row. Idempotent.
INSERT INTO "commission_policy_versions"
  ("id", "version", "calc_type", "value", "hold_days", "effective_from")
VALUES
  (gen_random_uuid()::text, 1, 'PERCENTAGE', 1000, 14, (now() AT TIME ZONE 'UTC'))
ON CONFLICT ("version") DO NOTHING;
