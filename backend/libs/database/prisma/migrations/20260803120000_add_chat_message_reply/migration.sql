-- Reply-to-message support: nullable self-relation on chat_messages.
-- Additive only — existing rows get NULL (no reply), no backfill needed.
-- ON DELETE SET NULL: messages are only ever soft-deleted (deletedAt), never
-- hard-deleted, so this only matters for a future hard-delete/cleanup job —
-- a reply must never be blocked or removed just because the message it
-- quotes was hard-deleted.

-- AlterTable
ALTER TABLE "chat_messages" ADD COLUMN "reply_to_message_id" TEXT;

-- CreateIndex
CREATE INDEX "chat_messages_reply_to_message_id_idx" ON "chat_messages"("reply_to_message_id");

-- AddForeignKey
ALTER TABLE "chat_messages" ADD CONSTRAINT "chat_messages_reply_to_message_id_fkey" FOREIGN KEY ("reply_to_message_id") REFERENCES "chat_messages"("id") ON DELETE SET NULL ON UPDATE CASCADE;
