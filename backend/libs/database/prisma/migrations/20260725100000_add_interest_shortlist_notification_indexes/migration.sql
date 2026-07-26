-- Composite (col, created_at) indexes so the paginated received/sent interest
-- lists, the shortlist list, and the notification list are each served from a
-- single index (WHERE <owner> ORDER BY created_at DESC) instead of a filter +
-- sort. Additive only — no data or existing index is touched.
--
-- NOTE for production scale (10M+ rows): create these CONCURRENTLY out-of-band
-- to avoid a write lock. On the current dataset they are effectively instant.

-- CreateIndex
CREATE INDEX "express_interests_receiver_id_created_at_idx" ON "express_interests"("receiver_id", "created_at");

-- CreateIndex
CREATE INDEX "express_interests_sender_id_created_at_idx" ON "express_interests"("sender_id", "created_at");

-- CreateIndex
CREATE INDEX "shortlists_user_id_created_at_idx" ON "shortlists"("user_id", "created_at");

-- CreateIndex
CREATE INDEX "notifications_user_id_created_at_idx" ON "notifications"("user_id", "created_at");
