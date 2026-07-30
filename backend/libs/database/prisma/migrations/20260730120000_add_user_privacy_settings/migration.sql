-- Per-user privacy visibility preferences. Additive only — two new columns on
-- the existing users table, each NOT NULL with a safe default so existing rows
-- are backfilled to the current behaviour (both off) without a data migration.

-- AlterTable
ALTER TABLE "users" ADD COLUMN "profile_visible_to_premium_only" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "users" ADD COLUMN "hide_photos_from_non_connections" BOOLEAN NOT NULL DEFAULT false;
