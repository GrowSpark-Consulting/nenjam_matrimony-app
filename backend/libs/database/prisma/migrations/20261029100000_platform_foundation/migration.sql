-- CreateEnum
CREATE TYPE "otp_purpose" AS ENUM ('AGENT_SIGN_IN');

-- CreateTable
CREATE TABLE "platform_settings" (
    "key" TEXT NOT NULL,
    "value" JSONB NOT NULL,
    "description" TEXT,
    "version" INTEGER NOT NULL DEFAULT 1,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "platform_settings_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "otp_challenges" (
    "id" TEXT NOT NULL,
    "purpose" "otp_purpose" NOT NULL,
    "phone_e164" TEXT NOT NULL,
    "code_hash" TEXT NOT NULL,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "consumed_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "otp_challenges_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "otp_challenges_purpose_phone_e164_created_at_idx" ON "otp_challenges"("purpose", "phone_e164", "created_at");

-- CreateIndex
CREATE INDEX "otp_challenges_expires_at_idx" ON "otp_challenges"("expires_at");


-- ---------------------------------------------------------------------------
-- Hand-written: constraints Prisma cannot express. Additive only: two new
-- tables, nothing existing is touched. No setting is seeded here — each
-- feature seeds its own keys in a later migration (the agent program's
-- sorts after this one).
-- ---------------------------------------------------------------------------

-- Same shape as permission keys: dotted lower-case, e.g. `referral.member_discount_bps`.
ALTER TABLE "platform_settings" ADD CONSTRAINT "platform_settings_key_format"
  CHECK ("key" ~ '^[a-z]+(\.[a-z_]+)+$');
ALTER TABLE "platform_settings" ADD CONSTRAINT "platform_settings_version_positive"
  CHECK ("version" >= 1);

ALTER TABLE "otp_challenges" ADD CONSTRAINT "otp_challenges_phone_e164_format"
  CHECK ("phone_e164" ~ '^\+[1-9][0-9]{7,14}$');
ALTER TABLE "otp_challenges" ADD CONSTRAINT "otp_challenges_attempts_non_negative"
  CHECK ("attempts" >= 0);
ALTER TABLE "otp_challenges" ADD CONSTRAINT "otp_challenges_expires_after_created"
  CHECK ("expires_at" > "created_at");
