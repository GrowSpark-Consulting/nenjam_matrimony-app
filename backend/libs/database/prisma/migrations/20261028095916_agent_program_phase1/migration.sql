-- CreateEnum
CREATE TYPE "agent_status" AS ENUM ('PENDING_APPROVAL', 'ACTIVE', 'REJECTED', 'SUSPENDED', 'TERMINATED');

-- CreateEnum
CREATE TYPE "referral_source" AS ENUM ('CODE_AT_SIGNUP', 'LINK_OR_QR', 'ADDED_BY_AGENT', 'ENTERED_AT_PAYMENT', 'ADMIN_SET');

-- CreateEnum
CREATE TYPE "attribution_status" AS ENUM ('ACTIVE', 'CONVERTED', 'EXPIRED', 'REJECTED');

-- CreateEnum
CREATE TYPE "agent_payout_method" AS ENUM ('UPI', 'BANK');

-- CreateTable
CREATE TABLE "agents" (
    "id" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "phone_hash" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "state" TEXT NOT NULL,
    "pan_last4" VARCHAR(4),
    "pan_encrypted" TEXT,
    "pan_verified_at" TIMESTAMP(3),
    "payout_details_set" BOOLEAN NOT NULL DEFAULT false,
    "status" "agent_status" NOT NULL DEFAULT 'PENDING_APPROVAL',
    "rejection_reason" TEXT,
    "approved_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "agents_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "referral_codes" (
    "id" TEXT NOT NULL,
    "agent_id" TEXT NOT NULL,
    "code" VARCHAR(8) NOT NULL,
    "is_primary" BOOLEAN NOT NULL DEFAULT false,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "referral_codes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "referral_attributions" (
    "id" TEXT NOT NULL,
    "user_id" TEXT,
    "phone_hash" TEXT NOT NULL,
    "agent_id" TEXT NOT NULL,
    "code_id" TEXT,
    "source" "referral_source" NOT NULL,
    "status" "attribution_status" NOT NULL DEFAULT 'ACTIVE',
    "window_ends_at" TIMESTAMP(3) NOT NULL,
    "needs_review" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "referral_attributions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "agent_refresh_tokens" (
    "id" TEXT NOT NULL,
    "agent_id" TEXT NOT NULL,
    "token_hash" TEXT NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "revoked_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "agent_refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "agent_device_tokens" (
    "id" TEXT NOT NULL,
    "agent_id" TEXT NOT NULL,
    "fcm_token" TEXT NOT NULL,
    "platform" "device_platform" NOT NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "agent_device_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "agent_payout_details" (
    "agent_id" TEXT NOT NULL,
    "method" "agent_payout_method" NOT NULL,
    "details_sealed" TEXT NOT NULL,
    "display" TEXT NOT NULL,
    "verified_at" TIMESTAMP(3),
    "changed_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "agent_payout_details_pkey" PRIMARY KEY ("agent_id")
);

-- CreateTable
CREATE TABLE "agent_applicants" (
    "phone_hash" TEXT NOT NULL,
    "phone_sealed" TEXT NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "agent_applicants_pkey" PRIMARY KEY ("phone_hash")
);

-- CreateTable
CREATE TABLE "referral_code_attempts" (
    "id" TEXT NOT NULL,
    "requester_key" TEXT NOT NULL,
    "code_key" TEXT,
    "attempted_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "referral_code_attempts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "agents_phone_key" ON "agents"("phone");

-- CreateIndex
CREATE UNIQUE INDEX "agents_phone_hash_key" ON "agents"("phone_hash");

-- CreateIndex
CREATE INDEX "agents_status_idx" ON "agents"("status");

-- CreateIndex
CREATE UNIQUE INDEX "referral_codes_code_key" ON "referral_codes"("code");

-- CreateIndex
CREATE INDEX "referral_codes_agent_id_idx" ON "referral_codes"("agent_id");

-- CreateIndex
CREATE UNIQUE INDEX "referral_attributions_user_id_key" ON "referral_attributions"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "referral_attributions_phone_hash_key" ON "referral_attributions"("phone_hash");

-- CreateIndex
CREATE INDEX "referral_attributions_agent_id_created_at_idx" ON "referral_attributions"("agent_id", "created_at");

-- CreateIndex
CREATE INDEX "referral_attributions_code_id_idx" ON "referral_attributions"("code_id");

-- CreateIndex
CREATE INDEX "referral_attributions_status_window_ends_at_idx" ON "referral_attributions"("status", "window_ends_at");

-- CreateIndex
CREATE UNIQUE INDEX "agent_refresh_tokens_token_hash_key" ON "agent_refresh_tokens"("token_hash");

-- CreateIndex
CREATE INDEX "agent_refresh_tokens_agent_id_idx" ON "agent_refresh_tokens"("agent_id");

-- CreateIndex
CREATE INDEX "agent_refresh_tokens_expires_at_idx" ON "agent_refresh_tokens"("expires_at");

-- CreateIndex
CREATE UNIQUE INDEX "agent_device_tokens_fcm_token_key" ON "agent_device_tokens"("fcm_token");

-- CreateIndex
CREATE INDEX "agent_device_tokens_agent_id_idx" ON "agent_device_tokens"("agent_id");

-- CreateIndex
CREATE INDEX "agent_applicants_expires_at_idx" ON "agent_applicants"("expires_at");

-- CreateIndex
CREATE INDEX "referral_code_attempts_requester_key_attempted_at_idx" ON "referral_code_attempts"("requester_key", "attempted_at");

-- CreateIndex
CREATE INDEX "referral_code_attempts_code_key_attempted_at_idx" ON "referral_code_attempts"("code_key", "attempted_at");

-- CreateIndex
CREATE INDEX "referral_code_attempts_attempted_at_idx" ON "referral_code_attempts"("attempted_at");

-- AddForeignKey
ALTER TABLE "referral_codes" ADD CONSTRAINT "referral_codes_agent_id_fkey" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "referral_attributions" ADD CONSTRAINT "referral_attributions_agent_id_fkey" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "referral_attributions" ADD CONSTRAINT "referral_attributions_code_id_fkey" FOREIGN KEY ("code_id") REFERENCES "referral_codes"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "referral_attributions" ADD CONSTRAINT "referral_attributions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "agent_refresh_tokens" ADD CONSTRAINT "agent_refresh_tokens_agent_id_fkey" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "agent_device_tokens" ADD CONSTRAINT "agent_device_tokens_agent_id_fkey" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "agent_payout_details" ADD CONSTRAINT "agent_payout_details_agent_id_fkey" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- Hand-written: constraints Prisma cannot express. Not in schema.prisma, so
-- `prisma migrate diff` does not see them; keep them here.
-- ---------------------------------------------------------------------------

-- Referral code format: "NM" + 6 characters from 23456789ABCDEFGHJKMNPQRSTUVWXYZ
-- (no 0, O, 1, I, L). Matches the generator and normalizeReferralCode().
ALTER TABLE "referral_codes"
  ADD CONSTRAINT "referral_codes_code_format_chk"
  CHECK ("code" ~ '^NM[2-9A-HJKMNP-Z]{6}$');

-- At most one primary code per agent.
CREATE UNIQUE INDEX "referral_codes_one_primary_per_agent_uq"
  ON "referral_codes" ("agent_id")
  WHERE "is_primary" = true;

-- A REJECTED agent must carry a reason: it is shown to the applicant. A blank
-- or whitespace-only reason is not a reason. Moving back to PENDING_APPROVAL
-- (re-applying) may clear it.
ALTER TABLE "agents"
  ADD CONSTRAINT "agents_rejected_has_reason_chk"
  CHECK ("status" <> 'REJECTED' OR ("rejection_reason" IS NOT NULL AND btrim("rejection_reason") <> ''));

-- A PAN cannot be marked verified unless a PAN is on file.
ALTER TABLE "agents"
  ADD CONSTRAINT "agents_pan_verified_needs_pan_chk"
  CHECK ("pan_verified_at" IS NULL OR "pan_encrypted" IS NOT NULL);
