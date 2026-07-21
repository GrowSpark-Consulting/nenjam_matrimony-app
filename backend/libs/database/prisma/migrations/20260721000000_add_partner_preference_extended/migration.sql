-- AlterTable
ALTER TABLE "partner_preferences" ADD COLUMN     "extended_preferences" JSONB NOT NULL DEFAULT '{}';
