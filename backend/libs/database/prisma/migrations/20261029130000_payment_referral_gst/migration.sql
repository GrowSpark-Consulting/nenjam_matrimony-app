-- CreateEnum
CREATE TYPE "payment_paid_by" AS ENUM ('MEMBER', 'AGENT', 'ADMIN_RECORDED');

-- CreateEnum
CREATE TYPE "payment_discount_source" AS ENUM ('NONE', 'REFERRAL_FIRST_PLAN');

-- AlterTable
ALTER TABLE "payment_transactions" ADD COLUMN     "discount_paise" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "discount_source" "payment_discount_source" NOT NULL DEFAULT 'NONE',
ADD COLUMN     "held_referral_code_id" TEXT,
ADD COLUMN     "is_first_paid_plan" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "list_amount_paise" INTEGER,
ADD COLUMN     "livemode" BOOLEAN,
ADD COLUMN     "paid_by" "payment_paid_by" NOT NULL DEFAULT 'MEMBER',
ADD COLUMN     "payment_source_hash" TEXT,
ADD COLUMN     "tax_paise" INTEGER,
ADD COLUMN     "tax_rate_bps" INTEGER,
ADD COLUMN     "taxable_amount_paise" INTEGER;

-- CreateTable
CREATE TABLE "payment_event_outbox" (
    "id" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "dedupe_key" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "last_error" TEXT,
    "delivered_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "payment_event_outbox_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "payment_event_outbox_dedupe_key_key" ON "payment_event_outbox"("dedupe_key");

-- CreateIndex
CREATE INDEX "payment_event_outbox_delivered_at_created_at_idx" ON "payment_event_outbox"("delivered_at", "created_at");


-- ---------------------------------------------------------------------------
-- Hand-written: constraints Prisma cannot express, and the GST setting.
-- Additive only: new enums, nullable/defaulted columns on payment_transactions
-- (existing rows keep their values; the new pricing columns stay NULL on
-- them), a new table and one new setting.
-- ---------------------------------------------------------------------------

-- The pricing snapshot is all-or-nothing, and when present it adds up:
-- taxable = list − discount, and the amount charged = taxable + GST.
ALTER TABLE "payment_transactions" ADD CONSTRAINT "payment_transactions_pricing_chk"
  CHECK (
    "discount_paise" >= 0
    AND ("discount_source" = 'NONE') = ("discount_paise" = 0)
    AND (
      ("list_amount_paise" IS NULL AND "taxable_amount_paise" IS NULL
        AND "tax_rate_bps" IS NULL AND "tax_paise" IS NULL)
      OR (
        "list_amount_paise" IS NOT NULL AND "taxable_amount_paise" IS NOT NULL
        AND "tax_rate_bps" IS NOT NULL AND "tax_paise" IS NOT NULL
        AND "tax_rate_bps" BETWEEN 0 AND 10000
        AND "tax_paise" >= 0
        AND "taxable_amount_paise" >= 0
        AND "taxable_amount_paise" = "list_amount_paise" - "discount_paise"
        AND "amount_inr" = "taxable_amount_paise" + "tax_paise"
      )
    )
  );

ALTER TABLE "payment_event_outbox" ADD CONSTRAINT "payment_event_outbox_type_chk"
  CHECK ("type" IN ('payment.succeeded', 'payment.refunded') AND "attempts" >= 0);

-- GST added on top of plan prices, in basis points (1800 = 18%). 0 until the
-- business is GST-registered (Raja, 29 Oct); a Super Admin changes it through
-- PUT /admin/settings/payment.gst_rate_bps. There is no default in code:
-- checkout refuses to charge while this row is missing.
INSERT INTO "platform_settings" ("key", "value", "description") VALUES
  ('payment.gst_rate_bps', '0'::jsonb,
   'GST added on top of plan prices, in basis points (1800 = 18%). 0 until the business is GST-registered.')
ON CONFLICT ("key") DO NOTHING;
