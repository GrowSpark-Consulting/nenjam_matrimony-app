-- Agent commissions, ledger and payouts. Additive only: new enums, new tables,
-- and one nullable column on "agents".

-- CreateEnum
CREATE TYPE "commission_calc_type" AS ENUM ('PERCENTAGE');

-- CreateEnum
CREATE TYPE "commission_status" AS ENUM ('ON_HOLD', 'AWAITING_VERIFICATION', 'IN_REVIEW', 'FROZEN', 'READY', 'APPROVED', 'PAID', 'CANCELLED', 'REVERSED');

-- CreateEnum
CREATE TYPE "agent_ledger_entry_type" AS ENUM ('CREDIT', 'REVERSAL', 'PAYOUT_DEBIT', 'PAYOUT_RELEASE', 'ADJUSTMENT');

-- CreateEnum
CREATE TYPE "agent_payout_status" AS ENUM ('CREATED', 'PAID', 'CANCELLED');

-- AlterTable
ALTER TABLE "agents" ADD COLUMN     "commission_policy_id" TEXT;

-- CreateTable
CREATE TABLE "commission_policy_versions" (
    "id" TEXT NOT NULL,
    "version" INTEGER NOT NULL,
    "calc_type" "commission_calc_type" NOT NULL,
    "value" INTEGER NOT NULL,
    "hold_days" INTEGER NOT NULL,
    "effective_from" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "commission_policy_versions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "commissions" (
    "id" TEXT NOT NULL,
    "agent_id" TEXT NOT NULL,
    "attribution_id" TEXT NOT NULL,
    "payment_id" TEXT NOT NULL,
    "phone_hash" TEXT NOT NULL,
    "policy_version_id" TEXT NOT NULL,
    "status" "commission_status" NOT NULL DEFAULT 'ON_HOLD',
    "calc_type" "commission_calc_type" NOT NULL,
    "rule_value" INTEGER NOT NULL,
    "base_paise" INTEGER,
    "amount_paise" INTEGER,
    "amount_paid_paise" INTEGER NOT NULL,
    "taxable_amount_paise" INTEGER NOT NULL,
    "credited_paise" INTEGER NOT NULL DEFAULT 0,
    "reversed_paise" INTEGER NOT NULL DEFAULT 0,
    "hold_until" TIMESTAMP(3) NOT NULL,
    "review_reasons" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "approved_at" TIMESTAMP(3),
    "paid_at" TIMESTAMP(3),
    "cancelled_at" TIMESTAMP(3),
    "payout_id" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "commissions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "agent_ledger_entries" (
    "id" TEXT NOT NULL,
    "agent_id" TEXT NOT NULL,
    "type" "agent_ledger_entry_type" NOT NULL,
    "amount_paise" INTEGER NOT NULL,
    "idempotency_key" TEXT NOT NULL,
    "commission_id" TEXT,
    "refund_id" TEXT,
    "payout_id" TEXT,
    "calc_type" TEXT,
    "rule_value" INTEGER,
    "rule_snapshot" JSONB,
    "reason" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "agent_ledger_entries_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "agent_payouts" (
    "id" TEXT NOT NULL,
    "agent_id" TEXT NOT NULL,
    "period" TEXT NOT NULL,
    "amount_paise" INTEGER NOT NULL,
    "tax_withheld_paise" INTEGER NOT NULL DEFAULT 0,
    "net_paise" INTEGER NOT NULL,
    "status" "agent_payout_status" NOT NULL DEFAULT 'CREATED',
    "reference" TEXT,
    "paid_at" TIMESTAMP(3),
    "cancel_reason" TEXT,
    "cancelled_at" TIMESTAMP(3),
    "created_by" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "agent_payouts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "commission_policy_versions_version_key" ON "commission_policy_versions"("version");

-- CreateIndex
CREATE INDEX "commission_policy_versions_effective_from_idx" ON "commission_policy_versions"("effective_from");

-- CreateIndex
CREATE UNIQUE INDEX "commissions_attribution_id_key" ON "commissions"("attribution_id");

-- CreateIndex
CREATE UNIQUE INDEX "commissions_payment_id_key" ON "commissions"("payment_id");

-- CreateIndex
CREATE UNIQUE INDEX "commissions_phone_hash_key" ON "commissions"("phone_hash");

-- CreateIndex
CREATE INDEX "commissions_agent_id_status_idx" ON "commissions"("agent_id", "status");

-- CreateIndex
CREATE INDEX "commissions_status_hold_until_idx" ON "commissions"("status", "hold_until");

-- CreateIndex
CREATE INDEX "commissions_payout_id_idx" ON "commissions"("payout_id");

-- CreateIndex
CREATE UNIQUE INDEX "agent_ledger_entries_idempotency_key_key" ON "agent_ledger_entries"("idempotency_key");

-- CreateIndex
CREATE INDEX "agent_ledger_entries_agent_id_created_at_idx" ON "agent_ledger_entries"("agent_id", "created_at");

-- CreateIndex
CREATE INDEX "agent_ledger_entries_commission_id_idx" ON "agent_ledger_entries"("commission_id");

-- CreateIndex
CREATE INDEX "agent_ledger_entries_payout_id_idx" ON "agent_ledger_entries"("payout_id");

-- CreateIndex
CREATE UNIQUE INDEX "agent_payouts_reference_key" ON "agent_payouts"("reference");

-- CreateIndex
CREATE INDEX "agent_payouts_agent_id_period_idx" ON "agent_payouts"("agent_id", "period");

-- CreateIndex
CREATE INDEX "agent_payouts_status_idx" ON "agent_payouts"("status");

-- AddForeignKey
ALTER TABLE "agents" ADD CONSTRAINT "agents_commission_policy_id_fkey" FOREIGN KEY ("commission_policy_id") REFERENCES "commission_policy_versions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commissions" ADD CONSTRAINT "commissions_agent_id_fkey" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commissions" ADD CONSTRAINT "commissions_attribution_id_fkey" FOREIGN KEY ("attribution_id") REFERENCES "referral_attributions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commissions" ADD CONSTRAINT "commissions_policy_version_id_fkey" FOREIGN KEY ("policy_version_id") REFERENCES "commission_policy_versions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "commissions" ADD CONSTRAINT "commissions_payout_id_fkey" FOREIGN KEY ("payout_id") REFERENCES "agent_payouts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "agent_ledger_entries" ADD CONSTRAINT "agent_ledger_entries_agent_id_fkey" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "agent_ledger_entries" ADD CONSTRAINT "agent_ledger_entries_commission_id_fkey" FOREIGN KEY ("commission_id") REFERENCES "commissions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "agent_ledger_entries" ADD CONSTRAINT "agent_ledger_entries_payout_id_fkey" FOREIGN KEY ("payout_id") REFERENCES "agent_payouts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "agent_payouts" ADD CONSTRAINT "agent_payouts_agent_id_fkey" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE RESTRICT ON UPDATE CASCADE;


-- ---------------------------------------------------------------------------
-- Hand-written: rules Prisma cannot express (CHECKs, a partial unique index,
-- the append-only trigger). Not in schema.prisma, so `prisma migrate diff`
-- does not see them; keep them here.
--
-- Money is integer PAISE throughout. No foreign key cascades: every FK above
-- is ON DELETE RESTRICT, so a money record is never removed as a side effect.
-- ---------------------------------------------------------------------------

-- Commission policy versions -------------------------------------------------

ALTER TABLE "commission_policy_versions"
  ADD CONSTRAINT "commission_policy_versions_values_chk"
  CHECK (
    "version" >= 1
    AND "value" >= 0
    AND "hold_days" >= 0
    -- PERCENTAGE is in basis points: at most 100%.
    AND ("calc_type" <> 'PERCENTAGE' OR "value" <= 10000)
  );

-- Commissions ----------------------------------------------------------------

-- The commission is between 0 and what the member paid (calculateCommission
-- already caps it; this keeps a bad write out). Null until the base is known.
ALTER TABLE "commissions"
  ADD CONSTRAINT "commissions_amount_between_chk"
  CHECK ("amount_paise" IS NULL OR ("amount_paise" >= 0 AND "amount_paise" <= "amount_paid_paise"));

ALTER TABLE "commissions"
  ADD CONSTRAINT "commissions_nonnegative_chk"
  CHECK (
    "amount_paid_paise" >= 0
    -- The taxable part is part of what was paid.
    AND "taxable_amount_paise" >= 0
    AND "taxable_amount_paise" <= "amount_paid_paise"
    AND "rule_value" >= 0
    AND ("base_paise" IS NULL OR "base_paise" >= 0)
    AND "credited_paise" >= 0
    AND "reversed_paise" >= 0
  );

-- Nothing is credited before the amount is known, never more than the amount,
-- and a refund cannot claw back more than was credited.
ALTER TABLE "commissions"
  ADD CONSTRAINT "commissions_credit_chk"
  CHECK (
    ("credited_paise" = 0 OR ("amount_paise" IS NOT NULL AND "credited_paise" <= "amount_paise"))
    AND "reversed_paise" <= "credited_paise"
  );

-- An approved or paid commission has an amount.
ALTER TABLE "commissions"
  ADD CONSTRAINT "commissions_approved_has_amount_chk"
  CHECK ("status" NOT IN ('APPROVED', 'PAID') OR "amount_paise" IS NOT NULL);

ALTER TABLE "commissions"
  ADD CONSTRAINT "commissions_paid_has_time_chk"
  CHECK ("status" <> 'PAID' OR "paid_at" IS NOT NULL);

-- Why a commission is IN_REVIEW: only the known reasons.
ALTER TABLE "commissions"
  ADD CONSTRAINT "commissions_review_reasons_chk"
  CHECK (
    "review_reasons" IS NOT NULL
    AND "review_reasons" <@ ARRAY['PAID_BY_AGENT', 'PAYMENT_SOURCE_REUSED', 'SELF_MATCH']::TEXT[]
  );

-- Agent ledger (append-only) --------------------------------------------------

-- A movement moves something, and its direction matches its type.
ALTER TABLE "agent_ledger_entries"
  ADD CONSTRAINT "agent_ledger_entries_amount_sign_chk"
  CHECK (
    "amount_paise" <> 0
    AND ("type" <> 'CREDIT' OR "amount_paise" > 0)
    AND ("type" <> 'REVERSAL' OR "amount_paise" < 0)
    AND ("type" <> 'PAYOUT_DEBIT' OR "amount_paise" < 0)
    AND ("type" <> 'PAYOUT_RELEASE' OR "amount_paise" > 0)
  );

-- An adjustment needs a reason; a blank one is not a reason.
ALTER TABLE "agent_ledger_entries"
  ADD CONSTRAINT "agent_ledger_entries_adjustment_reason_chk"
  CHECK ("type" <> 'ADJUSTMENT' OR ("reason" IS NOT NULL AND btrim("reason") <> ''));

-- Each type points at what it is about.
ALTER TABLE "agent_ledger_entries"
  ADD CONSTRAINT "agent_ledger_entries_links_chk"
  CHECK (
    ("type" NOT IN ('CREDIT', 'REVERSAL') OR "commission_id" IS NOT NULL)
    AND ("type" <> 'REVERSAL' OR "refund_id" IS NOT NULL)
    AND ("type" NOT IN ('PAYOUT_DEBIT', 'PAYOUT_RELEASE') OR "payout_id" IS NOT NULL)
  );

-- Rows are never changed or removed. A correction is a new ADJUSTMENT row.
CREATE FUNCTION "agent_ledger_entries_append_only"() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'agent_ledger_entries is append-only: % is not allowed', TG_OP
    USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE TRIGGER "agent_ledger_entries_append_only_trg"
  BEFORE UPDATE OR DELETE ON "agent_ledger_entries"
  FOR EACH ROW EXECUTE FUNCTION "agent_ledger_entries_append_only"();

-- Payouts ----------------------------------------------------------------------

-- One payout per agent per period, unless it was cancelled (a cancelled
-- payout frees the period). The reference is unique when set (a plain unique
-- index above; nulls do not collide).
CREATE UNIQUE INDEX "agent_payouts_one_active_per_period_uq"
  ON "agent_payouts" ("agent_id", "period")
  WHERE "status" <> 'CANCELLED';

ALTER TABLE "agent_payouts"
  ADD CONSTRAINT "agent_payouts_amounts_chk"
  CHECK (
    "period" ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'
    AND "amount_paise" > 0
    AND "tax_withheld_paise" >= 0
    AND "tax_withheld_paise" <= "amount_paise"
    AND "net_paise" = "amount_paise" - "tax_withheld_paise"
  );

-- A paid payout says how and when; a cancelled one says why.
ALTER TABLE "agent_payouts"
  ADD CONSTRAINT "agent_payouts_status_fields_chk"
  CHECK (
    ("status" <> 'PAID' OR ("reference" IS NOT NULL AND btrim("reference") <> '' AND "paid_at" IS NOT NULL))
    AND ("status" <> 'CANCELLED' OR ("cancel_reason" IS NOT NULL AND btrim("cancel_reason") <> '' AND "cancelled_at" IS NOT NULL))
  );
