-- Integrity hardening for the psychology (marriage-compatibility quiz) tables.
--
-- ADDITIVE ONLY. This migration adds constraints, one nullable column and
-- swaps one foreign key's delete rule. It does not UPDATE or DELETE a single
-- row, drops no column, and rewrites no table.
--
-- Preconditions (all hold for data produced by the seeder and the API; a
-- violation makes the statement fail cleanly, with nothing changed, rather
-- than altering data):
--   * at most one psychology_quizzes row has is_active = true
--   * no two quiz_questions in one quiz share an "order" or a "dimension"
-- Check before deploying against a database that was edited by hand:
--   SELECT count(*) FROM psychology_quizzes WHERE is_active;            -- <= 1
--   SELECT quiz_id, "order", count(*) FROM quiz_questions
--     GROUP BY 1, 2 HAVING count(*) > 1;                                -- no rows
--   SELECT quiz_id, dimension, count(*) FROM quiz_questions
--     GROUP BY 1, 2 HAVING count(*) > 1;                                -- no rows

-- 1. One question per position and per dimension within a quiz. The scorer
--    keys its cross-question rules by dimension, so a duplicate would silently
--    overwrite another question's result; a duplicate order makes "the quiz"
--    ambiguous. (Modelled in schema.prisma as @@unique.)
CREATE UNIQUE INDEX "quiz_questions_quiz_id_order_key" ON "quiz_questions"("quiz_id", "order");
CREATE UNIQUE INDEX "quiz_questions_quiz_id_dimension_key" ON "quiz_questions"("quiz_id", "dimension");

-- 2. At most one active quiz. Discover and quiz submission both take "the"
--    active quiz; two would let them disagree. A partial unique index is the
--    only way to say this in SQL (Prisma cannot model it, so it lives here
--    only). The application also picks deterministically if it ever sees two.
CREATE UNIQUE INDEX "psychology_quizzes_single_active_key" ON "psychology_quizzes"("is_active") WHERE "is_active";

-- 3. Which quiz version each response was given against. Nullable: existing
--    rows keep NULL, which the application treats as "current", so no member's
--    answers are invalidated by this migration.
ALTER TABLE "user_quiz_responses" ADD COLUMN "quiz_version" TEXT;

-- 4. Deleting a quiz must not silently delete every member's answers to it.
--    A retired quiz is deactivated, never deleted (an earlier migration
--    deleted one — safe only because it was verified empty). Deleting a USER
--    still cascades to their answers; that FK is untouched.
ALTER TABLE "user_quiz_responses" DROP CONSTRAINT "user_quiz_responses_quiz_id_fkey";
ALTER TABLE "user_quiz_responses" ADD CONSTRAINT "user_quiz_responses_quiz_id_fkey" FOREIGN KEY ("quiz_id") REFERENCES "psychology_quizzes"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- 5. Shape of the JSON columns. `answers` is a { questionId: optionKey } map,
--    `options` / `pair_rules` are arrays; anything else is unscoreable. The
--    application already tolerates bad data on read — this stops it being
--    written.
--
--    NOT VALID: enforced for every new or changed row, but existing rows are
--    not scanned or checked. That keeps this migration from ever failing on,
--    or having to touch, legacy data; the application's read-side guards cover
--    any pre-existing oddity. (VALIDATE CONSTRAINT can be run later, by hand,
--    once the table is known clean.)
ALTER TABLE "user_quiz_responses" ADD CONSTRAINT "user_quiz_responses_answers_is_object" CHECK (jsonb_typeof("answers") = 'object') NOT VALID;
ALTER TABLE "quiz_questions" ADD CONSTRAINT "quiz_questions_options_is_array" CHECK (jsonb_typeof("options") = 'array') NOT VALID;
ALTER TABLE "quiz_questions" ADD CONSTRAINT "quiz_questions_pair_rules_is_array" CHECK (jsonb_typeof("pair_rules") = 'array') NOT VALID;
