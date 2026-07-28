-- Chat message delivery states + idempotency + edit support.
-- Additive; existing rows default to SENT and are backfilled to READ where
-- they were already read, so no message loses state.

-- CreateEnum
CREATE TYPE "message_delivery_status" AS ENUM ('SENT', 'DELIVERED', 'READ');

-- AlterTable
ALTER TABLE "chat_messages"
  ADD COLUMN "client_message_id" TEXT,
  ADD COLUMN "status" "message_delivery_status" NOT NULL DEFAULT 'SENT',
  ADD COLUMN "delivered_at" TIMESTAMP(3),
  ADD COLUMN "edited_at" TIMESTAMP(3);

-- Backfill: already-read messages become READ (and count as delivered).
UPDATE "chat_messages"
  SET "status" = 'READ', "delivered_at" = COALESCE("read_at", "created_at")
  WHERE "is_read" = true;

-- CreateIndex (idempotency: one message per sender+clientMessageId; NULLs are
-- distinct in Postgres, so messages without a key are unconstrained)
CREATE UNIQUE INDEX "chat_messages_sender_id_client_message_id_key" ON "chat_messages"("sender_id", "client_message_id");

-- CreateIndex (reconnect-replay: undelivered messages in a room)
CREATE INDEX "chat_messages_room_id_status_idx" ON "chat_messages"("room_id", "status");
