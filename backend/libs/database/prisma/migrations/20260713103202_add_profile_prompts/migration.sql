-- CreateEnum
CREATE TYPE "prompt_category" AS ENUM ('PERSONALITY', 'MARRIAGE_COMPATIBILITY', 'FAMILY', 'CAREER');

-- CreateTable
CREATE TABLE "prompt_bank_items" (
    "id" TEXT NOT NULL,
    "category" "prompt_category" NOT NULL,
    "prompt_text" TEXT NOT NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "prompt_bank_items_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "user_profile_prompts" (
    "id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "prompt_id" TEXT NOT NULL,
    "answer_text" TEXT NOT NULL,
    "order" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_profile_prompts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "prompt_bank_items_category_idx" ON "prompt_bank_items"("category");

-- CreateIndex
CREATE INDEX "user_profile_prompts_user_id_idx" ON "user_profile_prompts"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "user_profile_prompts_user_id_prompt_id_key" ON "user_profile_prompts"("user_id", "prompt_id");

-- AddForeignKey
ALTER TABLE "user_profile_prompts" ADD CONSTRAINT "user_profile_prompts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "user_profile_prompts" ADD CONSTRAINT "user_profile_prompts_prompt_id_fkey" FOREIGN KEY ("prompt_id") REFERENCES "prompt_bank_items"("id") ON DELETE CASCADE ON UPDATE CASCADE;
