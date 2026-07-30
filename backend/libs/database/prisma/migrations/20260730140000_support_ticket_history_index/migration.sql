-- Optimize the ticket-history query (a user's own tickets, newest first).
-- Replace the single-column (user_id) index with a composite (user_id,
-- created_at): it serves the WHERE + ORDER BY as one ordered range scan and
-- still covers user_id-prefix lookups, so the standalone index is redundant.

-- DropIndex
DROP INDEX "support_tickets_user_id_idx";

-- CreateIndex
CREATE INDEX "support_tickets_user_id_created_at_idx" ON "support_tickets"("user_id", "created_at");
