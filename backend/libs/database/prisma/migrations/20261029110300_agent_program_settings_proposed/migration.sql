-- Agent program: PROPOSED values for the six settings that are not decided
-- yet. FOR ISHU'S APPROVAL: do not merge this migration until each value is
-- approved; change a value here only while this migration has never been
-- applied anywhere (afterwards change it with the admin settings API).
--
-- Data only. Sorts after 20261029110200_agent_program_settings_seed. Every
-- value can be changed later by a Super Admin (PUT /admin/settings/:key)
-- without a deploy. ON CONFLICT DO NOTHING keeps a value already set.
--
-- Reasons:
--   agent.access_token_ttl_seconds = 900 (15 minutes): the contract's own
--     example; a stolen access token is useful for a short time only, and the
--     portal refreshes silently.
--   agent.refresh_token_ttl_seconds = 2592000 (30 days): agents open the
--     portal now and then; a month keeps them signed in, and the token
--     rotates on every use with strict reuse detection.
--   agent.otp_resend_after_seconds = 30: the OTP service's own resend floor;
--     anything shorter makes a client that waits as told get 429, and the
--     settings validator refuses less than 30.
--   referral.code_validation_window_seconds = 3600 (one hour), with
--   referral.code_validation_ip_limit = 60 per IP per hour and
--   referral.code_validation_code_limit = 20 per code per hour: the public
--     code check reveals an agent's first name and last initial. The contract
--     suggests 10 per minute per IP and 20 per hour per code, but both limits
--     share ONE window here; one hour keeps 20 per code, and 60 per IP per hour
--     still allows a family behind one mobile carrier address (CGNAT) to type
--     codes while capping a scraper at 60 names an hour.

INSERT INTO "platform_settings" ("key", "value", "description") VALUES
  ('agent.access_token_ttl_seconds', '900'::jsonb,
   'Agent Portal access token lifetime, in seconds.'),
  ('agent.refresh_token_ttl_seconds', '2592000'::jsonb,
   'Agent Portal refresh token lifetime, in seconds (rotates on every use).'),
  ('agent.otp_resend_after_seconds', '30'::jsonb,
   'Seconds the portal tells an agent to wait before asking for another sign-in code. At least 30.'),
  ('referral.code_validation_ip_limit', '60'::jsonb,
   'Referral code checks allowed per requester (hashed IP) per window.'),
  ('referral.code_validation_code_limit', '20'::jsonb,
   'Referral code checks allowed per code per window.'),
  ('referral.code_validation_window_seconds', '3600'::jsonb,
   'The window, in seconds, for both referral code check limits.')
ON CONFLICT ("key") DO NOTHING;
