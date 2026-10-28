-- Membership catalogue v1: Free, Gold and Platinum, from
-- Nenjam_Membership_Plans.pdf (pages 1-3), with one product correction:
-- "Verified profiles only" browsing is available on EVERY plan, Free
-- included (the PDF marks it paid; product overrode that). The application
-- also refuses any future version that turns it off.
--
-- The one migration in this repo that ships data, on purpose: the Free plan
-- must exist in every environment that runs this code, and a seed script is
-- not guaranteed to have run. Every statement is idempotent and none
-- overwrites anything an administrator could have set:
--   * plans: insert, or refresh display fields only. An existing GOLD row
--     (from the old seeder) keeps its legacy price/limit columns untouched.
--   * versions: version 1 is inserted only if absent; later versions are
--     always new rows, never edits (see SubscriptionPlanVersion).
--   * durations: inserted UNPRICED and INACTIVE. The PDF sets lengths but no
--     prices, so nothing is purchasable until a price is set deliberately
--     (PlanCatalogAdminService / docs/membership/README.md). The CHECK
--     constraint on the table makes "active but unpriced" impossible.
--   * SILVER is retired: deactivated, never deleted.
--
-- Feature ids and value shapes are defined by
-- apps/api/src/modules/entitlements/catalog/feature-catalog.ts, which
-- validates every stored version on load.

-- 1. Plans --------------------------------------------------------------------
INSERT INTO "subscription_plans"
  ("id", "name", "display_name", "price_inr", "duration_days", "features", "limits",
   "is_active", "description", "tier", "display_order", "created_at", "updated_at")
VALUES
  (gen_random_uuid()::text, 'FREE', 'Free', 0, 0, '[]', '{}', true,
   'Create a profile, browse, get matches, send a few interests, reply to paid members. All safety and privacy features included.',
   0, 0, now(), now()),
  (gen_random_uuid()::text, 'GOLD', 'Gold', 0, 0, '[]', '{}', true,
   'Start conversations: chat, masked voice calls, contact numbers, full jathagam and porutham reports, power filters, search priority.',
   1, 1, now(), now()),
  (gen_random_uuid()::text, 'PLATINUM', 'Platinum', 0, 0, '[]', '{}', true,
   'Everything in Gold plus video calls, featured listing, incognito, let free members contact you, monthly profile makeover and astrologer time.',
   2, 2, now(), now())
ON CONFLICT ("name") DO UPDATE SET
  "display_name"  = EXCLUDED."display_name",
  "description"   = EXCLUDED."description",
  "tier"          = EXCLUDED."tier",
  "display_order" = EXCLUDED."display_order",
  "is_active"     = true,
  "updated_at"    = now();

UPDATE "subscription_plans"
SET "is_active" = false, "display_order" = 99, "updated_at" = now()
WHERE "name" = 'SILVER';

-- 2. Entitlements, version 1 --------------------------------------------------
INSERT INTO "subscription_plan_versions"
  ("id", "plan_id", "version", "entitlements", "effective_from", "change_note", "created_at")
SELECT gen_random_uuid()::text, p."id", 1, v."entitlements"::jsonb,
       TIMESTAMP '2026-01-01 00:00:00',
       'Initial catalogue from Nenjam_Membership_Plans.pdf. Verified-only browsing is free on every plan (product correction to the PDF).',
       now()
FROM "subscription_plans" p
JOIN (VALUES
  ('FREE', '{
    "profile.photos": {"limit": 5},
    "profile.video_intro": false,
    "profile.horoscope_upload": true,
    "profile.family_managed": true,
    "profile.badge": "NONE",
    "profile.makeover_sessions": {"limit": 0},
    "verification.id_review": "STANDARD",
    "search.verified_only": true,
    "discovery.daily_recommendations": {"limit": 5},
    "discovery.profile_views": {"limit": 30},
    "search.basic_filters": true,
    "search.community_filters": true,
    "search.power_filters": false,
    "search.nri_filters": true,
    "search.saved_searches": {"limit": 1},
    "discovery.mutual_matches": false,
    "interests.send": {"limit": 5},
    "interests.respond": true,
    "interests.personal_note": false,
    "shortlist.profiles": {"limit": 10},
    "chat.initiate": false,
    "chat.reply": true,
    "chat.read_receipts": false,
    "chat.accept_from_free_members": false,
    "calls.voice": false,
    "calls.video": false,
    "contacts.unlocks": {"limit": 0},
    "profile.full_details": false,
    "photos.private_access": false,
    "contacts.whatsapp_share": false,
    "horoscope.basic_score": true,
    "horoscope.full_jathagam": false,
    "horoscope.detailed_report": false,
    "horoscope.astrologer_minutes": {"limit": 0},
    "visibility.search_priority": "STANDARD",
    "visibility.boost_days": {"limit": 0},
    "visibility.featured": false,
    "insights.profile_viewers": "PREVIEW",
    "insights.profile_viewers_visible": {"limit": 3},
    "insights.shortlisted_by": "COUNT",
    "insights.performance_stats": "NONE",
    "privacy.incognito": false,
    "support.tier": "STANDARD"
  }'),
  ('GOLD', '{
    "profile.photos": {"limit": 15},
    "profile.video_intro": true,
    "profile.horoscope_upload": true,
    "profile.family_managed": true,
    "profile.badge": "GOLD",
    "profile.makeover_sessions": {"limit": 0},
    "verification.id_review": "STANDARD",
    "search.verified_only": true,
    "discovery.daily_recommendations": {"limit": 20},
    "discovery.profile_views": {"limit": null},
    "search.basic_filters": true,
    "search.community_filters": true,
    "search.power_filters": true,
    "search.nri_filters": true,
    "search.saved_searches": {"limit": 5},
    "discovery.mutual_matches": true,
    "interests.send": {"limit": 100},
    "interests.respond": true,
    "interests.personal_note": true,
    "shortlist.profiles": {"limit": null},
    "chat.initiate": true,
    "chat.reply": true,
    "chat.read_receipts": true,
    "chat.accept_from_free_members": false,
    "calls.voice": true,
    "calls.video": false,
    "contacts.unlocks": {"limit": 60, "perMonths": 3},
    "profile.full_details": true,
    "photos.private_access": true,
    "contacts.whatsapp_share": true,
    "horoscope.basic_score": true,
    "horoscope.full_jathagam": true,
    "horoscope.detailed_report": true,
    "horoscope.astrologer_minutes": {"limit": 0},
    "visibility.search_priority": "PRIORITY",
    "visibility.boost_days": {"limit": 7},
    "visibility.featured": false,
    "insights.profile_viewers": "FULL",
    "insights.profile_viewers_visible": {"limit": null},
    "insights.shortlisted_by": "FULL",
    "insights.performance_stats": "BASIC",
    "privacy.incognito": false,
    "support.tier": "PRIORITY"
  }'),
  ('PLATINUM', '{
    "profile.photos": {"limit": 20},
    "profile.video_intro": true,
    "profile.horoscope_upload": true,
    "profile.family_managed": true,
    "profile.badge": "PLATINUM",
    "profile.makeover_sessions": {"limit": 1},
    "verification.id_review": "PRIORITY",
    "search.verified_only": true,
    "discovery.daily_recommendations": {"limit": null},
    "discovery.profile_views": {"limit": null},
    "search.basic_filters": true,
    "search.community_filters": true,
    "search.power_filters": true,
    "search.nri_filters": true,
    "search.saved_searches": {"limit": null},
    "discovery.mutual_matches": true,
    "interests.send": {"limit": 300},
    "interests.respond": true,
    "interests.personal_note": true,
    "shortlist.profiles": {"limit": null},
    "chat.initiate": true,
    "chat.reply": true,
    "chat.read_receipts": true,
    "chat.accept_from_free_members": true,
    "calls.voice": true,
    "calls.video": true,
    "contacts.unlocks": {"limit": 200},
    "profile.full_details": true,
    "photos.private_access": true,
    "contacts.whatsapp_share": true,
    "horoscope.basic_score": true,
    "horoscope.full_jathagam": true,
    "horoscope.detailed_report": true,
    "horoscope.astrologer_minutes": {"limit": 15},
    "visibility.search_priority": "HIGHEST",
    "visibility.boost_days": {"limit": 15},
    "visibility.featured": true,
    "insights.profile_viewers": "FULL_WITH_TRENDS",
    "insights.profile_viewers_visible": {"limit": null},
    "insights.shortlisted_by": "FULL",
    "insights.performance_stats": "DETAILED",
    "privacy.incognito": true,
    "support.tier": "DEDICATED"
  }')
) AS v("plan", "entitlements") ON p."name"::text = v."plan"
ON CONFLICT ("plan_id", "version") DO NOTHING;

-- 3. Durations: lengths from the PDF, unpriced and inactive -------------------
INSERT INTO "subscription_plan_durations"
  ("id", "plan_id", "months", "duration_days", "bonus_days", "price_in_paise",
   "currency", "is_active", "display_order", "created_at", "updated_at")
SELECT gen_random_uuid()::text, p."id", d."months", d."days", 0, NULL,
       'INR', false, d."ord", now(), now()
FROM "subscription_plans" p
JOIN (VALUES
  ('GOLD', 3, 90, 1),
  ('GOLD', 6, 180, 2),
  ('PLATINUM', 3, 90, 1),
  ('PLATINUM', 6, 180, 2),
  ('PLATINUM', 12, 365, 3)
) AS d("plan", "months", "days", "ord") ON p."name"::text = d."plan"
ON CONFLICT ("plan_id", "months") DO NOTHING;
