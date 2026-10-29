-- Agent program: the DECIDED platform settings (Raja and Ishu, 28-29 Oct).
-- Data only, no schema change. Sorts after 20261029110100 (#155) and must
-- never reach a database before #155's migrations.
--
-- ON CONFLICT DO NOTHING: a value an admin has already set is kept. Values are
-- JSONB, never SQL NULL ('null'::jsonb is "not decided" where our parser
-- accepts it). The six settings that are not decided yet are in the next
-- migration, 20261029110300_agent_program_settings_proposed.

INSERT INTO "platform_settings" ("key", "value", "description") VALUES
  ('commission.auto_approve', 'true'::jsonb,
   'Agent commission is approved automatically once its hold ends (no manual review).'),
  ('commission.require_verified_profile', 'false'::jsonb,
   'Whether a member must have a verified profile for the referring agent to earn commission.'),
  ('referral.credit_window_days', '60'::jsonb,
   'Days after a member is attributed to an agent in which their first paid plan earns commission.'),
  ('referral.member_discount_bps', '500'::jsonb,
   'Discount on a referred member''s first paid plan, in basis points (500 = 5%).'),
  ('referral.discount_stacks_with_coupons', 'false'::jsonb,
   'Whether the referral discount combines with coupons. There is no coupon feature; keep false.'),
  ('referral.discount_only_in_credit_window', 'true'::jsonb,
   'The referral discount applies only inside the credit window.'),
  ('payout.minimum_amount_paise', '50000'::jsonb,
   'Smallest agent payout, in paise (50000 = Rs. 500).'),
  ('agent.client_draft_limit', '10'::jsonb,
   'How many client drafts an agent may keep open at once.'),
  ('agent.payout_details_wait_hours', '72'::jsonb,
   'Hours a newly changed payout destination waits before a payout may use it.'),
  ('commission.base', '"AMOUNT_PAID_EXCLUDING_GST"'::jsonb,
   'What the commission percentage is taken of: the taxable amount, without GST.'),
  ('commission.base_provisional', 'false'::jsonb,
   'Whether commission.base is still provisional. Decided by Raja on 28 Oct.'),
  ('payout.tax_withholding', 'null'::jsonb,
   'Tax withheld from agent payouts. null = not decided (waiting for the CA); payouts refuse any set value until the rule is built.')
ON CONFLICT ("key") DO NOTHING;
