-- AlterTable
ALTER TABLE "registration_steps" ADD COLUMN     "draft_data" JSONB NOT NULL DEFAULT '{}';
