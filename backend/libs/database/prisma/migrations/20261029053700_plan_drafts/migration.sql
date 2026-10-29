-- CreateEnum
CREATE TYPE "plan_draft_status" AS ENUM ('DRAFT', 'SUBMITTED', 'PUBLISHED', 'REJECTED', 'DISCARDED');

-- CreateTable
CREATE TABLE "subscription_plan_drafts" (
    "id" TEXT NOT NULL,
    "plan_id" TEXT NOT NULL,
    "base_version_id" TEXT,
    "entitlements" JSONB NOT NULL,
    "durations" JSONB NOT NULL DEFAULT '[]',
    "change_note" TEXT NOT NULL,
    "status" "plan_draft_status" NOT NULL DEFAULT 'DRAFT',
    "created_by_id" TEXT NOT NULL,
    "updated_by_id" TEXT NOT NULL,
    "submitted_by_id" TEXT,
    "submitted_at" TIMESTAMP(3),
    "decided_by_id" TEXT,
    "decided_at" TIMESTAMP(3),
    "decision_note" TEXT,
    "published_version_id" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "subscription_plan_drafts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "subscription_plan_drafts_plan_id_status_idx" ON "subscription_plan_drafts"("plan_id", "status");

-- CreateIndex
CREATE INDEX "subscription_plan_drafts_status_updated_at_idx" ON "subscription_plan_drafts"("status", "updated_at");

-- AddForeignKey
ALTER TABLE "subscription_plan_drafts" ADD CONSTRAINT "subscription_plan_drafts_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "subscription_plans"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- Hand-written. Additive only: one new enum and one new table.
-- ---------------------------------------------------------------------------

-- At most one open draft per plan, so two admins can't prepare conflicting
-- changes to the same plan at once.
CREATE UNIQUE INDEX "subscription_plan_drafts_one_open_per_plan"
  ON "subscription_plan_drafts" ("plan_id")
  WHERE "status" IN ('DRAFT', 'SUBMITTED');

-- Maker-checker, also at the database: a decided draft names a decider, and
-- the decider is never the submitter.
ALTER TABLE "subscription_plan_drafts" ADD CONSTRAINT "subscription_plan_drafts_decided_by_someone_else"
  CHECK (
    "status" NOT IN ('PUBLISHED', 'REJECTED')
    OR ("decided_by_id" IS NOT NULL AND "decided_at" IS NOT NULL
        AND "decided_by_id" IS DISTINCT FROM "submitted_by_id")
  );
ALTER TABLE "subscription_plan_drafts" ADD CONSTRAINT "subscription_plan_drafts_published_was_submitted"
  CHECK ("status" <> 'PUBLISHED' OR "submitted_by_id" IS NOT NULL);
