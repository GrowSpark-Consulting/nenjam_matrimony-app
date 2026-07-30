-- Support ticket categorization. Additive only: a new enum type plus a new
-- column on support_tickets with a safe default, so any existing rows are
-- backfilled without a separate data migration and no existing behaviour breaks.

-- CreateEnum
CREATE TYPE "support_ticket_type" AS ENUM ('CONTACT_SUPPORT', 'BUG_REPORT', 'FEATURE_REQUEST', 'APP_FEEDBACK');

-- AlterTable
ALTER TABLE "support_tickets" ADD COLUMN "type" "support_ticket_type" NOT NULL DEFAULT 'CONTACT_SUPPORT';
