-- The web address agent share links and QR codes start with (approved by
-- Ishu, 4 Nov). Data only, no schema change. Sorts after every migration on
-- main (the last is 20261103090200_agent_client_settings_seed).
--
-- Seeded as JSON null, which means "no link": link and qrPayload stay null
-- until a Super Admin sets the address in the admin settings (an admin can
-- only change a setting that has a row). No value is set here.
--
-- ON CONFLICT DO NOTHING: a value an admin has already set is kept.

INSERT INTO "platform_settings" ("key", "value", "description") VALUES
  ('referral.share_link_base_url', 'null'::jsonb,
   'Web address the referral share link and QR code start with: https, no path, query or fragment, never containing "agent". Null: no link and no QR.')
ON CONFLICT ("key") DO NOTHING;
