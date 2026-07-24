-- Steps 5 (Education & Career) and 6 (Physical Details) are skippable, but
-- their UserProfile columns were NOT NULL — writeProfileFromDraft() then
-- either wrote a fake placeholder (heightCm: 0) or omitted the field
-- entirely, which Prisma rejects as a missing required argument. Both
-- symptoms trace to the same root cause: these columns must allow NULL to
-- mean "the user never filled this in", same as every other optional
-- section's columns already do.
ALTER TABLE "user_profiles" ALTER COLUMN "height_cm" DROP NOT NULL;
ALTER TABLE "user_profiles" ALTER COLUMN "highest_education" DROP NOT NULL;
ALTER TABLE "user_profiles" ALTER COLUMN "profession" DROP NOT NULL;
