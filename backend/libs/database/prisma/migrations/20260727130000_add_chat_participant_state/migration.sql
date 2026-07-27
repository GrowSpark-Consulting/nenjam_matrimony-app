-- Per-user, per-room chat state (pin/mute/archive/mark-unread/delete-for-me/
-- read-position/notification override). Additive — new table only.

-- CreateTable
CREATE TABLE "chat_participant_states" (
    "id" TEXT NOT NULL,
    "room_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "is_pinned" BOOLEAN NOT NULL DEFAULT false,
    "is_muted" BOOLEAN NOT NULL DEFAULT false,
    "is_archived" BOOLEAN NOT NULL DEFAULT false,
    "mark_unread" BOOLEAN NOT NULL DEFAULT false,
    "last_read_message_id" TEXT,
    "last_read_at" TIMESTAMP(3),
    "deleted_until" TIMESTAMP(3),
    "custom_notification" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "chat_participant_states_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "chat_participant_states_room_id_user_id_key" ON "chat_participant_states"("room_id", "user_id");

-- CreateIndex
CREATE INDEX "chat_participant_states_user_id_idx" ON "chat_participant_states"("user_id");

-- AddForeignKey
ALTER TABLE "chat_participant_states" ADD CONSTRAINT "chat_participant_states_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "chat_rooms"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "chat_participant_states" ADD CONSTRAINT "chat_participant_states_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
