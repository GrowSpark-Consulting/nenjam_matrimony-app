-- Agent-added clients ("Way 2"): the switch and the expiry, decided by Ishu
-- (3 Nov). Data only, no schema change. Sorts after the Way 2 table
-- (20261103090000) and the consent-code purpose (20261103090100).
--
-- agent.client_draft_limit (10) is already seeded by
-- 20261029130100_agent_program_settings_seed and is not repeated here.
--
-- ON CONFLICT DO NOTHING: a value an admin has already set is kept. The
-- switch is seeded OFF; a missing switch is also OFF.

INSERT INTO "platform_settings" ("key", "value", "description") VALUES
  ('agent.clients_enabled', 'false'::jsonb,
   'Whether agents may add clients who then accept with a one-time code. Off until real SMS: with the test code only approved test numbers work.'),
  ('agent.client_draft_expiry_days', '14'::jsonb,
   'Days an agent-added client draft stays open: from creation, and again from submit. Then it expires.')
ON CONFLICT ("key") DO NOTHING;
