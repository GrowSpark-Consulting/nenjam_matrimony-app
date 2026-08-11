-- Indexes for the three read paths whose plans showed a full sort or a
-- whole-table scan. All three are additive: no column, constraint or row is
-- touched, and each can be reversed with a plain DROP INDEX.
--
-- Verified with EXPLAIN before adding (see the @@index comments in schema.prisma):
--   * chat history paging read the GLOBAL created_at index backward with
--     room_id as a Filter, discarding other rooms' messages until it had a page
--   * the Discover/Search feed sorted every profile of the matching gender on
--     every page request (Sort Key: created_at DESC)
--   * "who viewed me" grouped a user's entire view history by viewer

-- CreateIndex
CREATE INDEX "chat_messages_room_id_created_at_idx" ON "chat_messages"("room_id", "created_at");

-- CreateIndex
CREATE INDEX "profile_views_viewed_user_id_viewer_id_idx" ON "profile_views"("viewed_user_id", "viewer_id");

-- CreateIndex
CREATE INDEX "user_profiles_gender_created_at_idx" ON "user_profiles"("gender", "created_at");
