-- AlterEnum
ALTER TYPE "user_status" ADD VALUE 'BLOCKED';

-- CreateTable
CREATE TABLE "member_notes" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "author_id" TEXT NOT NULL,
    "author_name" TEXT,
    "note" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "member_notes_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "member_notes_user_id_idx" ON "member_notes"("user_id");

-- CreateIndex
CREATE INDEX "member_notes_author_id_idx" ON "member_notes"("author_id");

-- AddForeignKey
ALTER TABLE "member_notes" ADD CONSTRAINT "member_notes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
