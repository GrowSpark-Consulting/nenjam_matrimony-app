-- Agent-added clients ("Way 2"): an agent's draft of a client's profile, and
-- the pointer to the newest one-time code sent to a client's phone.
--
-- New tables only; nothing existing changes. The new otp_purpose value is in
-- the next migration on its own (20261103090100): Postgres does not let a
-- value added by ALTER TYPE ... ADD VALUE be used in the transaction that
-- added it, so it is kept apart from everything else.
--
-- The rules Prisma cannot express are at the end: the partial indexes, the
-- CHECKs on which columns are set in which status, and the triggers (allowed
-- status changes, locked after submit, only a DRAFT may be deleted, no
-- TRUNCATE).

-- CreateEnum
CREATE TYPE "agent_client_draft_status" AS ENUM ('DRAFT', 'WAITING_FOR_CLIENT', 'ACCEPTED', 'REJECTED', 'EXPIRED');

-- CreateTable
CREATE TABLE "agent_client_drafts" (
    "id" TEXT NOT NULL,
    "agent_id" TEXT NOT NULL,
    "status" "agent_client_draft_status" NOT NULL DEFAULT 'DRAFT',
    "phone_hash" TEXT NOT NULL,
    "phone_sealed" TEXT,
    "phone_masked" TEXT NOT NULL,
    "display_name" TEXT NOT NULL,
    "details_sealed" TEXT,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "submitted_at" TIMESTAMP(3),
    "accepted_at" TIMESTAMP(3),
    "closed_at" TIMESTAMP(3),
    "closed_reason" TEXT,
    "member_id" TEXT,
    "attribution_id" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "agent_client_drafts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "agent_client_consent_codes" (
    "phone_hash" TEXT NOT NULL,
    "challenge_id" TEXT NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "agent_client_consent_codes_pkey" PRIMARY KEY ("phone_hash")
);

-- CreateIndex
CREATE UNIQUE INDEX "agent_client_drafts_attribution_id_key" ON "agent_client_drafts"("attribution_id");

-- CreateIndex
CREATE INDEX "agent_client_drafts_agent_id_created_at_idx" ON "agent_client_drafts"("agent_id", "created_at");

-- CreateIndex
CREATE INDEX "agent_client_drafts_member_id_idx" ON "agent_client_drafts"("member_id");

-- CreateIndex
CREATE INDEX "agent_client_consent_codes_expires_at_idx" ON "agent_client_consent_codes"("expires_at");

-- AddForeignKey
ALTER TABLE "agent_client_drafts" ADD CONSTRAINT "agent_client_drafts_agent_id_fkey" FOREIGN KEY ("agent_id") REFERENCES "agents"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "agent_client_drafts" ADD CONSTRAINT "agent_client_drafts_member_id_fkey" FOREIGN KEY ("member_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "agent_client_drafts" ADD CONSTRAINT "agent_client_drafts_attribution_id_fkey" FOREIGN KEY ("attribution_id") REFERENCES "referral_attributions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- ---------------------------------------------------------------------------
-- Rules Prisma cannot express
-- ---------------------------------------------------------------------------

-- One OPEN draft (DRAFT or WAITING_FOR_CLIENT) per agent and phone. Closed
-- ones do not count, so an agent may add a phone again after a draft expired
-- (but not after the client rejected it: the service refuses that).
CREATE UNIQUE INDEX "agent_client_drafts_one_open_per_agent_phone_uq"
  ON "agent_client_drafts" ("agent_id", "phone_hash")
  WHERE "status" IN ('DRAFT', 'WAITING_FOR_CLIENT');

-- The client's invitations: the waiting drafts for her phone.
CREATE INDEX "agent_client_drafts_waiting_phone_idx"
  ON "agent_client_drafts" ("phone_hash")
  WHERE "status" = 'WAITING_FOR_CLIENT';

-- "Did this client reject this agent before?"
CREATE INDEX "agent_client_drafts_rejected_idx"
  ON "agent_client_drafts" ("agent_id", "phone_hash")
  WHERE "status" = 'REJECTED';

-- The daily expiry: open drafts by when they close.
CREATE INDEX "agent_client_drafts_open_expiry_idx"
  ON "agent_client_drafts" ("expires_at")
  WHERE "status" IN ('DRAFT', 'WAITING_FOR_CLIENT');

-- The phone hash, the masked phone and the display name are never blank.
ALTER TABLE "agent_client_drafts"
  ADD CONSTRAINT "agent_client_drafts_not_blank_chk"
  CHECK (btrim("phone_hash") <> '' AND btrim("phone_masked") <> '' AND btrim("display_name") <> '');

-- A DRAFT has not been submitted; a waiting, accepted or rejected one has. An
-- EXPIRED one may be either (an unsubmitted draft expires too).
ALTER TABLE "agent_client_drafts"
  ADD CONSTRAINT "agent_client_drafts_submitted_chk"
  CHECK (
    ("status" = 'DRAFT' AND "submitted_at" IS NULL)
    OR ("status" IN ('WAITING_FOR_CLIENT', 'ACCEPTED', 'REJECTED') AND "submitted_at" IS NOT NULL)
    OR "status" = 'EXPIRED'
  );

-- An ACCEPTED draft records when, and the attribution it created.
ALTER TABLE "agent_client_drafts"
  ADD CONSTRAINT "agent_client_drafts_accepted_chk"
  CHECK ("status" <> 'ACCEPTED' OR ("accepted_at" IS NOT NULL AND "attribution_id" IS NOT NULL));

-- Only an ACCEPTED draft has an acceptance time, a member or an attribution.
ALTER TABLE "agent_client_drafts"
  ADD CONSTRAINT "agent_client_drafts_only_accepted_links_chk"
  CHECK ("status" = 'ACCEPTED' OR ("accepted_at" IS NULL AND "member_id" IS NULL AND "attribution_id" IS NULL));

-- REJECTED and EXPIRED drafts, and only they, have a closing time.
ALTER TABLE "agent_client_drafts"
  ADD CONSTRAINT "agent_client_drafts_closed_chk"
  CHECK (("status" IN ('REJECTED', 'EXPIRED')) = ("closed_at" IS NOT NULL));

-- An EXPIRED draft, and only it, says why it closed, from a fixed list.
ALTER TABLE "agent_client_drafts"
  ADD CONSTRAINT "agent_client_drafts_closed_reason_chk"
  CHECK (("status" = 'EXPIRED') = ("closed_reason" IS NOT NULL));

ALTER TABLE "agent_client_drafts"
  ADD CONSTRAINT "agent_client_drafts_closed_reason_values_chk"
  CHECK ("closed_reason" IS NULL OR "closed_reason" IN ('TIMED_OUT', 'CLIENT_ACCEPTED_ANOTHER', 'CLIENT_ALREADY_MEMBER', 'AGENT_TERMINATED'));

-- The client's details exist exactly while the draft is open: closing a draft
-- (accepted, rejected or expired) deletes the agent's copy.
ALTER TABLE "agent_client_drafts"
  ADD CONSTRAINT "agent_client_drafts_details_chk"
  CHECK (("status" IN ('DRAFT', 'WAITING_FOR_CLIENT')) = ("details_sealed" IS NOT NULL));

-- The sealed phone exists while the draft is open, and stays on a REJECTED
-- one (so the "never again" block can be re-hashed in a pepper rotation).
ALTER TABLE "agent_client_drafts"
  ADD CONSTRAINT "agent_client_drafts_phone_sealed_chk"
  CHECK (("status" IN ('DRAFT', 'WAITING_FOR_CLIENT', 'REJECTED')) = ("phone_sealed" IS NOT NULL));

ALTER TABLE "agent_client_drafts"
  ADD CONSTRAINT "agent_client_drafts_expires_chk"
  CHECK ("expires_at" > "created_at");

ALTER TABLE "agent_client_consent_codes"
  ADD CONSTRAINT "agent_client_consent_codes_not_blank_chk"
  CHECK (btrim("phone_hash") <> '' AND btrim("challenge_id") <> '');

-- Status changes, locking and deletion. Allowed changes:
--   DRAFT              -> WAITING_FOR_CLIENT (submit), EXPIRED
--   WAITING_FOR_CLIENT -> ACCEPTED, REJECTED, EXPIRED
-- ACCEPTED, REJECTED and EXPIRED are final. Once a draft leaves DRAFT what the
-- client sees is locked: the only change allowed to the sealed columns is to
-- clear them when it closes. A closed draft never changes again, except that
-- its member link is cleared when the member deletes her account (the foreign
-- key's SET NULL). Only a DRAFT may be deleted (discarded): a REJECTED row is
-- the lasting record that blocks the agent from that phone.
CREATE FUNCTION "agent_client_drafts_guard"() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD."status" <> 'DRAFT' THEN
      RAISE EXCEPTION 'agent_client_drafts: only a DRAFT may be deleted (this one is %)', OLD."status"
        USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN OLD;
  END IF;

  IF NEW."id" IS DISTINCT FROM OLD."id"
     OR NEW."agent_id" IS DISTINCT FROM OLD."agent_id"
     OR NEW."phone_hash" IS DISTINCT FROM OLD."phone_hash"
     OR NEW."created_at" IS DISTINCT FROM OLD."created_at" THEN
    RAISE EXCEPTION 'agent_client_drafts: id, agent_id, phone_hash and created_at never change'
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF NEW."status" IS DISTINCT FROM OLD."status" AND NOT (
       (OLD."status" = 'DRAFT' AND NEW."status" IN ('WAITING_FOR_CLIENT', 'EXPIRED'))
    OR (OLD."status" = 'WAITING_FOR_CLIENT' AND NEW."status" IN ('ACCEPTED', 'REJECTED', 'EXPIRED'))
  ) THEN
    RAISE EXCEPTION 'agent_client_drafts: % -> % is not allowed', OLD."status", NEW."status"
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF NEW."status" = 'ACCEPTED' AND OLD."status" <> 'ACCEPTED' AND NEW."member_id" IS NULL THEN
    RAISE EXCEPTION 'agent_client_drafts: an accepted draft names the member it created'
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF OLD."status" = 'WAITING_FOR_CLIENT' AND (
       NEW."display_name" IS DISTINCT FROM OLD."display_name"
    OR NEW."phone_masked" IS DISTINCT FROM OLD."phone_masked"
    OR NEW."submitted_at" IS DISTINCT FROM OLD."submitted_at"
    OR NEW."expires_at" IS DISTINCT FROM OLD."expires_at"
    OR (NEW."details_sealed" IS DISTINCT FROM OLD."details_sealed" AND NEW."details_sealed" IS NOT NULL)
    OR (NEW."phone_sealed" IS DISTINCT FROM OLD."phone_sealed" AND NEW."phone_sealed" IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'agent_client_drafts: a submitted draft is locked'
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF OLD."status" IN ('ACCEPTED', 'REJECTED', 'EXPIRED') AND (
       (to_jsonb(NEW) - 'member_id' - 'updated_at') IS DISTINCT FROM (to_jsonb(OLD) - 'member_id' - 'updated_at')
    OR (NEW."member_id" IS DISTINCT FROM OLD."member_id" AND NEW."member_id" IS NOT NULL)
  ) THEN
    RAISE EXCEPTION 'agent_client_drafts: a closed draft never changes'
      USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER "agent_client_drafts_guard_trg"
  BEFORE UPDATE OR DELETE ON "agent_client_drafts"
  FOR EACH ROW EXECUTE FUNCTION "agent_client_drafts_guard"();

-- TRUNCATE fires no row trigger, and TRUNCATE agents CASCADE would empty this
-- table too. Refused, as on the money tables: the rejected rows are a lasting
-- record of a client saying no.
CREATE FUNCTION "agent_client_drafts_no_truncate"() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% holds client consent records: % is not allowed', TG_TABLE_NAME, TG_OP
    USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE TRIGGER "agent_client_drafts_no_truncate_trg"
  BEFORE TRUNCATE ON "agent_client_drafts"
  FOR EACH STATEMENT EXECUTE FUNCTION "agent_client_drafts_no_truncate"();
