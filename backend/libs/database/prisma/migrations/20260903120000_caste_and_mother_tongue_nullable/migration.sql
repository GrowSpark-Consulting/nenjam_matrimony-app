-- Caste and mother tongue are no longer collected during onboarding.
--
-- They used to be asked on the "Your Religion" step. The product dropped both
-- questions, which left the two columns NOT NULL while nothing in the signup
-- flow supplied a value — so writeProfileFromDraft() could only have written a
-- fabricated placeholder or omitted the field and had Postgres reject the row.
-- Both are wrong for the same reason heightCm/highestEducation/profession were
-- made nullable in 20260724115818: absence must be allowed to mean "never
-- filled in" rather than being faked into a value the member never gave.
--
-- Safe for existing rows. DROP NOT NULL only widens what the column accepts;
-- every caste and mother tongue already stored stays exactly as it is, and the
-- columns are deliberately NOT dropped — Edit Profile still edits them, the
-- matching engine still reads them (null-tolerantly: see
-- partner-preference-where.builder.ts's SelfAttributes and
-- profile-feed.mapper.ts's `?? ''`), and existing members' data must survive.
ALTER TABLE "user_profiles" ALTER COLUMN "caste" DROP NOT NULL;
ALTER TABLE "user_profiles" ALTER COLUMN "mother_tongue" DROP NOT NULL;
