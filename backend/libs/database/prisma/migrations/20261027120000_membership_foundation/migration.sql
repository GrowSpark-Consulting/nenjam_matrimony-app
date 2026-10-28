-- Membership foundation: Free / Gold / Platinum plans, versioned entitlements,
-- subscription lifecycle history, usage metering and webhook idempotency.
--
-- ADDITIVE ONLY. Adds one enum value, new enums, new tables, and nullable or
-- defaulted columns on existing tables. It does not UPDATE or DELETE a single
-- row, drops nothing, and rewrites no table. The catalogue rows themselves are
-- inserted by the NEXT migration (20261027120100_membership_catalog), because
-- Postgres cannot use the new PLATINUM enum value inside the transaction that
-- adds it.
--
-- Existing members are unaffected: a member with no subscription row resolves
-- to the Free plan, and nothing is enforced until MEMBERSHIP_ENFORCEMENT_MODE
-- is set to `enforce` (see docs/membership/README.md).

-- CreateEnum
CREATE TYPE "subscription_source" AS ENUM ('PURCHASE', 'ADMIN_GRANT');

-- CreateEnum
CREATE TYPE "subscription_event_type" AS ENUM ('CHECKOUT_CREATED', 'ACTIVATED', 'PAYMENT_FAILED', 'CANCELLED_AT_PERIOD_END', 'EXPIRED', 'REFUNDED', 'PARTIALLY_REFUNDED', 'GRANTED', 'EXTENDED', 'REVOKED', 'ENTITLEMENTS_UPGRADED');

-- CreateEnum
CREATE TYPE "payment_webhook_status" AS ENUM ('PROCESSED', 'IGNORED');

-- AlterEnum
ALTER TYPE "subscription_plan_name" ADD VALUE 'PLATINUM';

-- AlterTable
ALTER TABLE "payment_transactions" ADD COLUMN     "currency" TEXT NOT NULL DEFAULT 'INR',
ADD COLUMN     "refunded_amount" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "refunded_at" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "subscription_plans" ADD COLUMN     "description" TEXT,
ADD COLUMN     "display_order" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "tier" INTEGER NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "user_subscriptions" ADD COLUMN     "activated_at" TIMESTAMP(3),
ADD COLUMN     "cancellation_reason" TEXT,
ADD COLUMN     "cancelled_at" TIMESTAMP(3),
ADD COLUMN     "currency" TEXT,
ADD COLUMN     "duration_id" TEXT,
ADD COLUMN     "plan_version_id" TEXT,
ADD COLUMN     "price_in_paise" INTEGER,
ADD COLUMN     "source" "subscription_source" NOT NULL DEFAULT 'PURCHASE';

-- CreateTable
CREATE TABLE "subscription_plan_durations" (
    "id" TEXT NOT NULL,
    "plan_id" TEXT NOT NULL,
    "months" INTEGER NOT NULL,
    "duration_days" INTEGER NOT NULL,
    "bonus_days" INTEGER NOT NULL DEFAULT 0,
    "price_in_paise" INTEGER,
    "currency" TEXT NOT NULL DEFAULT 'INR',
    "is_active" BOOLEAN NOT NULL DEFAULT false,
    "display_order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "subscription_plan_durations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "subscription_plan_versions" (
    "id" TEXT NOT NULL,
    "plan_id" TEXT NOT NULL,
    "version" INTEGER NOT NULL,
    "entitlements" JSONB NOT NULL,
    "effective_from" TIMESTAMP(3) NOT NULL,
    "change_note" TEXT,
    "created_by_id" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "subscription_plan_versions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "subscription_events" (
    "id" TEXT NOT NULL,
    "subscription_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "type" "subscription_event_type" NOT NULL,
    "from_status" "subscription_status",
    "to_status" "subscription_status",
    "actor_id" TEXT,
    "metadata" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "subscription_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payment_webhook_events" (
    "id" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "event_id" TEXT NOT NULL,
    "event_type" TEXT NOT NULL,
    "status" "payment_webhook_status" NOT NULL,
    "order_id" TEXT,
    "payment_id" TEXT,
    "payload_sha256" TEXT NOT NULL,
    "detail" TEXT,
    "received_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "payment_webhook_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "membership_usage_counters" (
    "user_id" TEXT NOT NULL,
    "feature" TEXT NOT NULL,
    "period_key" TEXT NOT NULL,
    "used" INTEGER NOT NULL DEFAULT 0,
    "period_ends_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "membership_usage_counters_pkey" PRIMARY KEY ("user_id","feature","period_key")
);

-- CreateTable
CREATE TABLE "membership_usage_items" (
    "user_id" TEXT NOT NULL,
    "feature" TEXT NOT NULL,
    "period_key" TEXT NOT NULL,
    "item_key" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "membership_usage_items_pkey" PRIMARY KEY ("user_id","feature","period_key","item_key")
);

-- CreateIndex
CREATE UNIQUE INDEX "subscription_plan_durations_plan_id_months_key" ON "subscription_plan_durations"("plan_id", "months");

-- CreateIndex
CREATE INDEX "subscription_plan_versions_plan_id_effective_from_idx" ON "subscription_plan_versions"("plan_id", "effective_from");

-- CreateIndex
CREATE UNIQUE INDEX "subscription_plan_versions_plan_id_version_key" ON "subscription_plan_versions"("plan_id", "version");

-- CreateIndex
CREATE INDEX "subscription_events_subscription_id_created_at_idx" ON "subscription_events"("subscription_id", "created_at");

-- CreateIndex
CREATE INDEX "subscription_events_user_id_created_at_idx" ON "subscription_events"("user_id", "created_at");

-- CreateIndex
CREATE INDEX "payment_webhook_events_order_id_idx" ON "payment_webhook_events"("order_id");

-- CreateIndex
CREATE UNIQUE INDEX "payment_webhook_events_provider_event_id_key" ON "payment_webhook_events"("provider", "event_id");

-- CreateIndex
-- Replay protection: the event-id header is not signed, so the signed body
-- itself (by hash) must be unique too.
CREATE UNIQUE INDEX "payment_webhook_events_provider_payload_sha256_key" ON "payment_webhook_events"("provider", "payload_sha256");

-- CreateIndex
CREATE INDEX "membership_usage_counters_period_ends_at_idx" ON "membership_usage_counters"("period_ends_at");

-- CreateIndex
CREATE INDEX "user_subscriptions_user_id_status_end_date_idx" ON "user_subscriptions"("user_id", "status", "end_date");

-- AddForeignKey
ALTER TABLE "subscription_plan_durations" ADD CONSTRAINT "subscription_plan_durations_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "subscription_plans"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscription_plan_versions" ADD CONSTRAINT "subscription_plan_versions_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "subscription_plans"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_subscriptions" ADD CONSTRAINT "user_subscriptions_plan_version_id_fkey" FOREIGN KEY ("plan_version_id") REFERENCES "subscription_plan_versions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_subscriptions" ADD CONSTRAINT "user_subscriptions_duration_id_fkey" FOREIGN KEY ("duration_id") REFERENCES "subscription_plan_durations"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscription_events" ADD CONSTRAINT "subscription_events_subscription_id_fkey" FOREIGN KEY ("subscription_id") REFERENCES "user_subscriptions"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "subscription_events" ADD CONSTRAINT "subscription_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "membership_usage_counters" ADD CONSTRAINT "membership_usage_counters_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "membership_usage_items" ADD CONSTRAINT "membership_usage_items_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- Integrity rules Prisma cannot model (CHECK constraints live in SQL only).
-- An active duration must carry a positive price, so an unpriced plan can
-- never be sold for nothing; usage can never go negative.
ALTER TABLE "subscription_plan_durations"
  ADD CONSTRAINT "subscription_plan_durations_months_check" CHECK ("months" > 0),
  ADD CONSTRAINT "subscription_plan_durations_duration_days_check" CHECK ("duration_days" > 0),
  ADD CONSTRAINT "subscription_plan_durations_bonus_days_check" CHECK ("bonus_days" >= 0),
  ADD CONSTRAINT "subscription_plan_durations_price_check" CHECK ("price_in_paise" IS NULL OR "price_in_paise" > 0),
  ADD CONSTRAINT "subscription_plan_durations_active_priced_check" CHECK (NOT "is_active" OR "price_in_paise" IS NOT NULL);

ALTER TABLE "subscription_plan_versions"
  ADD CONSTRAINT "subscription_plan_versions_version_check" CHECK ("version" > 0),
  ADD CONSTRAINT "subscription_plan_versions_entitlements_object_check" CHECK (jsonb_typeof("entitlements") = 'object');

ALTER TABLE "membership_usage_counters"
  ADD CONSTRAINT "membership_usage_counters_used_check" CHECK ("used" >= 0);

ALTER TABLE "payment_transactions"
  ADD CONSTRAINT "payment_transactions_refunded_amount_check" CHECK ("refunded_amount" >= 0);
