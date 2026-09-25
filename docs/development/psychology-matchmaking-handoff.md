# Nenjam Matrimony — Psychology-Based Matchmaking: Complete Technical & Product Handoff

> **⚠ Partly superseded (2026-09-25).** The matching model, answer storage/retake behaviour and API behaviour described in Parts 2, 6, 7, 8, 13, 14, 16, 17, 20 and 22 below were redesigned. Psychology is now a bounded *ranking-only refinement* on top of the unchanged 100-point model (not a 15-weight component / "115 total"), retakes are cooldown-limited, and no psychology-derived number is exposed. **Read [psychology-backend-contract.md](psychology-backend-contract.md) first; it wins wherever the two disagree.** Quiz content, matrices and flag rules here are still accurate.

**Status as of this document:** Backend fully implemented, tested, and connected to live Discover matching. Flutter/frontend implementation has **not started** — see Part 17.

This document is the single source of truth for the psychology matchmaking feature. It was written by directly inspecting the current codebase (schema, migrations, seed data, backend modules, tests, and the Flutter repository) on 2026-09-24, not by summarizing prior conversation. Every claim below is grounded in a specific file; where the Flutter side was verified, it was verified by reading the actual files, not assumed.

---

## PART 1 — Executive Overview

### Why this feature exists

Nenjam's existing matching (`CompatibilityService`) only ever compared demographics and stated preferences — age, religion, community, education, location, lifestyle habits, plus profile completeness/verification/activity. None of that measures whether two people are likely to actually get along day-to-day as a married couple: how they handle disagreements, what they expect from money, family involvement, children, and daily life together. Psychology matchmaking adds exactly that missing layer.

### What "psychology compatibility" means in Nenjam

It means: **how aligned two people's answers are across 10 scenario-based, marriage-relevant questions** — conflict style, money, family/in-law boundaries, career adaptability, household division, emotional support, personal space, decision-making, children, and life-stage timeline. Each pair of answers is scored against a hand-reviewed, pre-approved table (not a generic "how close are the numbers" formula), and certain pairings are explicitly flagged as worth a direct conversation.

### What it does NOT mean

- **It is not a prediction of marital success.** Nobody's future is being forecast. It measures alignment on a defined set of questions, nothing more.
- **It is not a personality test.** There is no Big Five/OCEAN, no MBTI, no trait typing anywhere in this system (the old OCEAN quiz that used to exist here was deliberately retired — see Part 4).
- **It is not a clinical or diagnostic tool.** No question or output makes any claim about mental health.
- **It is not the primary matching factor.** It is a small, additive ingredient in the existing match score (see Part 13) — existing preferences (religion, community, age, etc.) remain dominant.

### Simple end-to-end diagram

```
Flutter (not yet built)
    │  GET /psychology/quiz/active   →  10 questions, no scoring internals
    │  POST /psychology/quiz/submit  →  { quizId, answers: [{questionId, selectedKey}] }
    ▼
Psychology API (NestJS, apps/api/src/modules/psychology)
    │  validates + upserts UserQuizResponse.answers  { questionId: selectedKey }
    ▼
Answer storage (Postgres: user_quiz_responses)
    │  (only reached when TWO users are being compared for a match)
    ▼
Pairwise psychology engine (calculatePsychologyCompatibility)
    │  per-question score (approved matrix) + flags + Q9 ceiling + cross-question rules
    ▼
Psychology compatibility result (0-100 + flags), consumed internally by...
    ▼
Existing matching engine (CompatibilityService, matches/scoring/)
    │  psychology becomes ONE more weighted component (15 of ~115 points)
    ▼
Discover score (`overallCompatibility` in the API response Flutter already reads)
```

### The actual production flow, in one sentence

Today, in production, this pipeline runs end-to-end on **every single Discover request** — but for virtually every user right now (since almost nobody has taken the new quiz yet), it short-circuits after two cheap database lookups and contributes nothing, leaving every existing score byte-for-byte identical to before this feature existed. It only ever activates for a specific pair when **both** people have completed the quiz.

---

## PART 2 — Complete Feature Flow

**A. User opens psychology quiz** — not yet built in Flutter. A route exists (`RouteNames.psychologyQuiz = '/registration/psychology-quiz'`, `lib/core/router/app_router.dart:428-432`) and is reachable from 4 places in the app (profile intelligence hub, profile completion card, edit-profile flow, profile review page), but it currently opens the **old, mock-only OCEAN quiz UI** — see Part 17.

**B. Flutter gets active quiz** — `GET /psychology/quiz/active`. Backend: `PsychologyController.getActiveQuiz()` → `PsychologyService.getActiveQuiz()` → `PsychologyRepository.findActiveQuiz()` + `findQuestionsForQuiz()`. Returns the quiz + all 10 questions with their options — never `scoringType` or `pairRules`.

**C. User answers 10 questions** — client-side only, no backend involvement until submit.

**D. Flutter submits answers** — `POST /psychology/quiz/submit`, body `{ quizId, answers: [{questionId, selectedKey}] }`.

**E. Backend validates answers** — `PsychologyService.submitAnswers()` checks, in order: active quiz exists; `quizId` matches it; no duplicate `questionId`s; every `questionId` belongs to the active quiz; **all 10** questions answered (no partial submission); every `selectedKey` is a real option for its question. Any failure → `400 BadRequestException` with a specific message. See Part 8.

**F. Backend stores/upserts response** — `PsychologyRepository.upsertUserResponse(userId, quizId, answersMap)`, keyed on the `(userId, quizId)` unique constraint. `answers` is stored as `{ questionId: selectedKey }` — nothing else.

**G. User can retake** — calling `POST /psychology/quiz/submit` again with the same `quizId` overwrites the existing row in place (upsert, not a new row). A response to a **retired** quiz (different `quizId`) is never touched — see Part 4/9.

**H. Two users have completed responses** — this is the precondition for anything in steps I–N to run. Nothing here happens until a Discover request scores a specific seeker/candidate pair where both have a response to the *current* active quiz.

**I. Psychology engine retrieves both responses** — `PsychologyMatchContextService.loadContext(seekerId, candidateIds)` (`matches/scoring/psychology/psychology-match-context.service.ts`). Fetches the active quiz, the seeker's own response (short-circuits to empty if none), then — only if the seeker has one — the quiz's questions and a **batch** fetch of all candidates' responses in one query.

**J–K. Each question is compared / per-question score** — `calculatePsychologyCompatibility()` (`psychology/scoring/psychology-compatibility.calculator.ts`) looks up each question's two selected keys in the approved static matrix (`compatibility-matrix.data.ts`).

**L. Flags are generated** — read live from that question's own `QuizQuestion.pairRules`, whenever the two selected keys match a defined pair.

**M. Cross-question rules are applied** — Q10↔Q9 severity escalation, Q8-D↔Q3 informational note (Part 12).

**N. Overall psychology compatibility is calculated** — the (rounded) average of the 10 per-question scores, then the Q9 hard-axis ceiling is applied if triggered (Part 9/12).

**O. Psychology score is passed into the real matching system** — `CompatibilityService.scoreMany()`'s new optional 4th parameter, and each `ScorableProfile`'s new optional `psychologyAnswers` field. `PSYCHOLOGY_COMPATIBILITY_SIGNAL` reuses the same `calculatePsychologyCompatibility()` function to produce one weighted component (Part 13).

**P. Final Discover compatibility score is produced** — `CompatibilityService.score()`'s `overall` field, which becomes `overallCompatibility` in the API response (`profile-feed.mapper.ts`).

**Q. Flutter displays whatever backend exposes** — today, that's `overallCompatibility` (already read by existing Discover UI) and `aiMatchPercent`. The dedicated `psychologyMatchPercent` field is **still hardcoded to `0`** — see Part 13/14/17 for the precise, important nuance here.

---

## PART 3 — The 10 Questions (verbatim)

Source: `backend/libs/database/src/seeders/quiz.seeder.ts`. Quiz id: `marriage-compat-v1`. All text below is quoted exactly as stored — do not paraphrase it further in any client implementation.

### Q1 — `nenjam-mc-q01-v1`
- **Dimension:** `conflict_style`
- **scoringType:** `MUST_ALIGN`
- **Question:** "You and your partner disagree about something that matters to you. What's your natural first move?"
- **Options:** A. "I want to talk it through right away, until we reach a resolution" (value 1) · B. "I need some time alone to process before I can discuss it calmly" (value 2) · C. "I look for a quick middle ground so we can move on" (value 3) · D. "I usually let my partner take the lead on resolving it" (value 4)
- **Why it exists:** Conflict-handling pattern is one of the best-documented predictors of relationship strain (demand/withdraw dynamics).
- **pairRules:** `(A,B)` → flag, soft, "Agree on a pause-and-return rule for disagreements" · `(D,D)` → flag, soft, "Decide who initiates tough conversations"

### Q2 — `nenjam-mc-q02-v1`
- **Dimension:** `financial_philosophy`
- **scoringType:** `MUST_ALIGN`
- **Question:** "How do you picture handling money once you're married?"
- **Options:** A. "Full transparency — joint accounts, joint decisions on everything, big or small" (1) · B. "Joint accounts/goals for big things (house, savings), personal autonomy for day-to-day spending" (2) · C. "Mostly separate finances, with agreed contributions to shared expenses" (3) · D. "One of us should primarily manage and take the lead on household finances" (4)
- **Why it exists:** Money is the most commonly reported source of marital conflict — usually over control/transparency expectations, not income.
- **pairRules:** `(A,C)` → flag, medium, "Discuss money management before marriage, not after" · `(D,D)` → flag, soft, "Clarify who owns financial decisions"

### Q3 — `nenjam-mc-q03-v1`
- **Dimension:** `family_boundaries`
- **scoringType:** `MUST_ALIGN`
- **Question:** "How involved do you want your (and your partner's) parents/extended family to be in your day-to-day married life and decisions?"
- **Options:** A. "Very involved — we consult them on most major decisions as a family unit" (1) · B. "Involved in major events and big decisions, but we decide our day-to-day independently" (2) · C. "Respectful distance — we keep them informed but make our own decisions" (3) · D. "Minimal — we prefer to keep our married life largely separate from extended family" (4)
- **Why it exists:** High-stakes in the Indian context specifically, where joint/semi-joint family involvement expectations vary widely between families that look similar on paper.
- **pairRules:** `(A,D)` → **dealbreaker**, high, "This is a fundamental difference — involve both families in this conversation" · `(A,C)` → flag, medium, "Align on how involved extended family should be"

### Q4 — `nenjam-mc-q04-v1`
- **Dimension:** `career_adaptability`
- **scoringType:** `COMPLEMENTARY_TOLERANT`
- **Question:** "If one of your careers required relocating, long hours, or a big time investment for a few years, how do you picture your marriage adapting?"
- **Options:** A. "I expect my career to take priority at times, and my partner to be willing to adapt around it" (1) · B. "We'd weigh it together each time and prioritize whichever opportunity benefits the family more" (2) · C. "My career matters, but I'd want stability/location to take priority over big career swings" (3) · D. "I expect to scale back my career for family life if needed" (4)
- **Why it exists:** One of the few dimensions where *similarity* is the risk, not the safety net — two people who both expect to be accommodated is worse than one leading, one adapting.
- **pairRules:** `(A,A)` → flag, medium, "Discuss how you'll actually decide when careers compete"

### Q5 — `nenjam-mc-q05-v1`
- **Dimension:** `household_division`
- **scoringType:** `MUST_ALIGN`
- **Question:** "Picture you're both working full-time. How do you imagine dividing cooking, cleaning, finances, and other home responsibilities?"
- **Options:** A. "Strictly split down the middle — roughly 50/50 on everything" (1) · B. "Divided by whoever is better at or prefers each task, not by any fixed rule" (2) · C. "More traditional — one of us primarily runs the home, the other handles outside-the-home matters" (3) · D. "We outsource/hire help where we can and split whatever's left" (4)
- **Why it exists:** Unspoken assumptions about "who does what," often inherited from upbringing, are a major source of quiet resentment in dual-income households.
- **pairRules:** `(A,C)` → flag, medium, "Clarify what 'traditional' means to each of you" · `(C,C)` → flag, medium, same message + a note that this flag is conditional on a follow-up question that doesn't exist yet (see Part 11)

### Q6 — `nenjam-mc-q06-v1`
- **Dimension:** `emotional_support`
- **scoringType:** `COMPLEMENTARY_TOLERANT`
- **Question:** "When you're stressed or upset, what helps you most from a partner?"
- **Options:** A. "Just listening, without trying to fix or advise" (1) · B. "Practical help — solutions, advice, a plan to fix the problem" (2) · C. "Space alone first, then support once I've settled" (3) · D. "Physical closeness or quiet reassurance, more than words" (4)
- **Why it exists:** Classic "venting vs. fixing" mismatch — a very common everyday friction point that's usually just a communication-style gap, not a real risk.
- **pairRules:** `(A,B)` → flag, soft, "Ask before you respond — do they want you to just listen, or help fix it?" · `(C,A)`, `(C,B)`, `(C,D)` → each flag, soft, "Agree on a signal for 'give me a few minutes'"

### Q7 — `nenjam-mc-q07-v1`
- **Dimension:** `personal_space`
- **scoringType:** `MUST_ALIGN`
- **Question:** "How much independent time — own friends, hobbies, time alone — do you want to keep once you're married?"
- **Options:** A. "A lot — I value my own interests and independent time strongly" (1) · B. "A healthy balance of together-time and me-time" (2) · C. "I'd prefer we spend most of our time and activities together" (3) · D. "It depends on the season of life / how I'm feeling" (4)
- **Why it exists:** A foundational relationship-satisfaction axis independent of how much two people love each other.
- **pairRules:** `(A,C)` → flag, medium, "You have very different needs for space — discuss what 'enough together time' looks like" · `(A,A)` → flag, soft, informational note that two independent lives can drift apart · `(C,C)` → flag, soft, informational note that shared-everything can tip into an enmeshed dynamic

### Q8 — `nenjam-mc-q08-v1`
- **Dimension:** `decision_making`
- **scoringType:** `COMPLEMENTARY_TOLERANT`
- **Question:** "For a major life decision (buying a home, having a child, changing cities), what's your ideal process?"
- **Options:** A. "We each share our view, then decide together as equals" (1) · B. "I prefer to lead and make the final call after hearing my partner's input" (2) · C. "I'm comfortable letting my partner lead and supporting their decision" (3) · D. "We should involve our families before deciding" (4)
- **Why it exists:** If both people expect final say, or both expect to defer, the couple either fights for control repeatedly or drifts with nobody steering.
- **pairRules:** `(B,B)` → flag, medium, "You both expect to lead major decisions — decide how you'll handle disagreement"
- **Special behavior:** Option D ("involve our families") triggers the Q8↔Q3 cross-question informational note — see Part 12.

### Q9 — `nenjam-mc-q09-v1`
- **Dimension:** `children`
- **scoringType:** `HARD_AXIS` (the only one)
- **Question:** "What best describes where you stand on having children?"
- **Options:** A. "I want children fairly soon, with both partners actively co-parenting" (1) · B. "I want children, and expect a more traditional division of parenting roles" (2) · C. "I'm open either way — I'd want to decide together over time" (3) · D. "I don't want children, or want to decide on this much later" (4)
- **Why it exists:** One of the few genuinely close-to-binary compatibility axes — wanting vs. not wanting children is a real, largely non-negotiable divide.
- **pairRules:** `(A,D)` → **dealbreaker**, hard, "You and this match have different expectations about having children" · `(B,D)` → same, hard, same message · `(C,A)`, `(C,B)`, `(C,D)` → each flag, soft, "Set a timeline for this conversation"
- **Special behavior:** Drives the overall-score ≤40% ceiling (Part 12) and the Q10↔Q9 escalation rule (Part 12).

### Q10 — `nenjam-mc-q10-v1`
- **Dimension:** `life_stage_timeline`
- **scoringType:** `MUST_ALIGN`
- **Question:** "How do you picture the first few years after marriage?"
- **Options:** A. "Settling into a stable home and routine fairly quickly" (1) · B. "Continuing to build career or personal goals before settling into a fixed routine" (2) · C. "Traveling and experiencing life together before taking on major responsibilities" (3) · D. "Focusing on starting a family soon" (4)
- **Why it exists:** Two people can share every long-term value and still clash on *sequencing* — this question exists to catch that specifically, distinct from *whether* (Q9).
- **pairRules:** `(B,D)` → flag, medium, sequencing-conflict message (cross-references Q9) · `(C,D)` → same

---

## PART 4 — Database / Prisma Changes

File: `backend/libs/database/prisma/schema.prisma`.

### `PsychologyQuiz` (lines 486-498)
```prisma
model PsychologyQuiz {
  id          String             @id @default(uuid())
  title       String
  description String?
  version     String             @default("1.0")
  isActive    Boolean            @default(true) @map("is_active")
  createdAt   DateTime           @default(now()) @map("created_at")
  updatedAt   DateTime           @updatedAt @map("updated_at")
  questions   QuizQuestion[]
  responses   UserQuizResponse[]
  @@map("psychology_quizzes")
}
```
Purpose: versioned questionnaire container. Generic on purpose — it carries no OCEAN-specific (or marriage-quiz-specific) fields, so retiring/replacing the whole questionnaire again in future is "seed a new row with a new id," never a schema change. **"Active quiz" concept:** `isActive: true`, exactly one row expected by convention (enforced by the seeder's usage, not a DB constraint — `findActiveQuiz()` uses `findFirst`, not `findUnique`).

### `QuizQuestion` (lines 507-524)
```prisma
model QuizQuestion {
  id           String              @id @default(uuid())
  quizId       String              @map("quiz_id")
  dimension    String
  scoringType  QuestionScoringType @map("scoring_type")
  questionText String              @map("question_text")
  options      Json                // [{ key, label, value }]
  pairRules    Json  @default("[]") @map("pair_rules")  // [{ pair, type, severity, message }]
  order        Int
  createdAt    DateTime            @default(now()) @map("created_at")
  quiz         PsychologyQuiz      @relation(fields: [quizId], references: [id], onDelete: Cascade)
  @@index([quizId])
  @@index([dimension])
  @@map("quiz_questions")
}
```
`options`/`pairRules` are opaque `Json` — content-agnostic, scored entirely by the psychology module; this table has no scoring knowledge itself. `QuestionScoringType` enum (schema.prisma:1088-1094): `MUST_ALIGN | COMPLEMENTARY_TOLERANT | HARD_AXIS`.

### `UserQuizResponse` (lines 533-547)
```prisma
model UserQuizResponse {
  id          String         @id @default(uuid())
  userId      String         @map("user_id")
  quizId      String         @map("quiz_id")
  answers     Json           // { questionId: selectedOptionKey }
  completedAt DateTime       @default(now()) @map("completed_at")
  updatedAt   DateTime       @updatedAt @map("updated_at")
  quiz        PsychologyQuiz @relation(fields: [quizId], references: [id], onDelete: Cascade)
  user        User           @relation(fields: [userId], references: [id], onDelete: Cascade)
  @@unique([userId, quizId])
  @@index([userId])
  @@map("user_quiz_responses")
}
```
`answers` is the **single canonical field** — no separate "result"/score is ever stored here (see Part 9 for why). `@@unique([userId, quizId])` is what makes retake = upsert, and what guarantees a *retired* quiz's old responses are never overwritten by a new questionnaire version (different `quizId` → different row).

### What was retired (the old OCEAN structure)
Before this feature, `QuizQuestion` had `oceanDomain OceanDomain` (enum `O|C|E|A|N`) and `reverseScored Boolean` instead of `dimension`/`scoringType`/`options`/`pairRules`; `UserQuizResponse` had `oceanScore Json` instead of the plain `answers`-only shape. A 20-question OCEAN/Big-Five quiz was seeded under it. It was **retired, not deprecated-in-place** — the rows were deleted, not just deactivated.

### The migration
File: `backend/libs/database/prisma/migrations/20260923140000_marriage_psychology_questionnaire/migration.sql`. Hand-written (not `prisma migrate dev`-generated — that command hung trying to reach a shadow database through the pooled Neon connection). Verified via a live read-only query **immediately before writing it**:
```
psychology_quizzes:   1 row   (the old OCEAN quiz)
quiz_questions:      20 rows  (the old OCEAN questions)
user_quiz_responses:  0 rows  (confirmed: no code path in the app had ever written to this table)
```
So deletion was safe by construction — there was no real user data to lose. The migration: (1) deletes the OCEAN quiz + its 20 questions by their exact seeded ids, (2) drops the `ocean_domain` index/columns and the enum type, (3) creates the `question_scoring_type` enum, (4) adds `dimension`/`scoring_type`/`options`/`pair_rules` as `NOT NULL` (safe — the table was empty at that point in the same migration), (5) drops `ocean_score`, adds `updated_at`. Applied via `prisma migrate deploy` (not `migrate dev`) after this same read-only check; verified afterward that `quiz_questions`/`psychology_quizzes` held only the new 10-question content and `user_quiz_responses` remained at 0.

No secrets, credentials, or connection strings are reproduced anywhere in the migration or this document.

---

## PART 5 — Seed Data

File: `backend/libs/database/src/seeders/quiz.seeder.ts` — run via `pnpm db:seed` → `libs/database/src/seed.ts` → `seedQuiz(prisma)` (step 2 of 4: plans → **quiz** → prompts → admin).

- **Quiz id:** `marriage-compat-v1` (hardcoded, deterministic — `upsert` on this exact id, so re-running the seeder never duplicates it).
- **Question ids:** `nenjam-mc-q01-v1` through `nenjam-mc-q10-v1` — deterministic, one per question, also upserted.
- **10 questions**, each with exactly 4 options (`{key, label, value}`, keys always `A|B|C|D`, values always `1|2|3|4` matching option order).
- **`pairRules`** are stored as plain arrays of `{pair: [key,key], type: 'flag'|'dealbreaker', severity: 'soft'|'medium'|'high'|'hard', message}` — written inline per question in `QUESTIONS` (the same content documented verbatim in Part 3/11).
- **`scoringType`** is stored per question using the real `QuestionScoringType` Prisma enum import — not a string literal, so a typo would fail to compile.
- **Deterministic/idempotent:** every write is an `upsert` keyed by a fixed id — safe to re-run in any environment (dev, CI, staging) without creating duplicates or drifting content.

**What was retired from the old seed:** the entire 20-question OCEAN generator (4 questions × 5 traits O/C/E/A/N, 5-point Likert `reverseScored` flags, a `flip(6-score)-then-average` formula that was only ever described in a comment and never actually implemented in code). None of that logic exists anywhere in the codebase anymore.

---

## PART 6 — Backend Module Architecture

```
backend/apps/api/src/modules/psychology/
├── psychology.module.ts                              — module registration
├── controllers/
│   └── psychology.controller.ts                       — the 3 HTTP endpoints
├── services/
│   └── psychology.service.ts                          — answer storage/validation orchestration
├── repositories/
│   └── psychology.repository.ts                       — all Prisma access for this feature
├── dto/
│   └── submit-quiz-answers.dto.ts                      — POST /submit request validation
├── entities/
│   ├── quiz-question.entity.ts                         — public quiz/question response shape
│   └── user-quiz-response.entity.ts                    — public "my answers" response shape
├── scoring/
│   ├── compatibility-matrix.data.ts                    — the approved 10×4×4 numeric matrix
│   ├── psychology-compatibility.calculator.ts           — pure two-user scoring function
│   ├── psychology-compatibility.service.ts              — standalone orchestration (fetch + calculate)
│   └── psychology-compatibility.types.ts                — result/flag/status types
└── tests/
    ├── compatibility-matrix.data.spec.ts
    ├── psychology-compatibility.calculator.spec.ts
    ├── psychology-compatibility.service.spec.ts
    └── psychology.service.spec.ts

backend/apps/api/src/modules/matches/scoring/psychology/    (lives in the MATCHES module, not psychology)
├── psychology-compatibility.signal.ts                   — the CompatibilityService signal plug-in
└── psychology-match-context.service.ts                  — fetches quiz data for a live Discover request
```

### File-by-file

**`psychology.module.ts`** — registers `PsychologyController`, `PsychologyService`, `PsychologyRepository`, `PsychologyCompatibilityService` as providers; `exports: [PsychologyRepository]` so `MatchesModule` can read quiz/response data (Part 13). `PrismaService` is global, so no `DatabaseModule` import needed.

**`controllers/psychology.controller.ts`** — the only file with `@Controller`/HTTP decorators in this feature. Route base `psychology/quiz`, guarded by `@UseGuards(FirebaseAuthGuard)` on the whole controller. Thin — delegates every method straight to `PsychologyService`. See Part 7 for exact contracts.

**`services/psychology.service.ts`** — answer storage + validation only. **Does not compute any score.** `getActiveQuiz()`, `getMyResponse(userId)`, `submitAnswers(userId, dto)`. Contains all the validation rules documented in Part 8, plus the mapping from raw Prisma rows to public entities (which strips `pairRules`/`scoringType` — see the class doc comment, line 1-5 of the entity file).

**`repositories/psychology.repository.ts`** — every Prisma query for this feature, in one place: `findActiveQuiz()`, `findQuestionsForQuiz(quizId)`, `findUserResponse(userId, quizId)`, `upsertUserResponse(userId, quizId, answers)`, and `findResponsesForUsers(userIds, quizId)` (the batch method added for live Discover scoring — Part 13).

**`dto/submit-quiz-answers.dto.ts`** — `class-validator`-decorated. `QuizAnswerDto {questionId: string, selectedKey: string}`, `SubmitQuizAnswersDto {quizId: string, answers: QuizAnswerDto[]}` (`@ArrayMinSize(1)`). Enforced by the global `ValidationPipe`.

**`entities/quiz-question.entity.ts`** — `QuizOptionEntity {key, label, value}`, `QuizQuestionEntity {id, order, dimension, questionText, options}` (no `scoringType`/`pairRules`), `ActiveQuizEntity {id, title, description, version, questions}`.

**`entities/user-quiz-response.entity.ts`** — `UserQuizAnswerEntity {questionId, dimension, questionText, selectedKey, selectedLabel}` (joined against the question bank for display, not a second stored copy), `UserQuizResponseEntity {quizId, answers, completedAt, updatedAt}`.

**`scoring/compatibility-matrix.data.ts`** — the approved 10×4×4 numeric matrix (Part 10), plus `pairLookupKey(a,b)` (order-independent lookup). Pure data + one helper function, no logic.

**`scoring/psychology-compatibility.calculator.ts`** — `calculatePsychologyCompatibility(questions, answersA, answersB): CalculatorResult`. Pure function, no I/O. This is the single scoring implementation reused by both the standalone engine and the live-matching signal (Part 9/13).

**`scoring/psychology-compatibility.service.ts`** — `PsychologyCompatibilityService.computeForUsers(userIdA, userIdB)`. Orchestration wrapper: fetches the active quiz + both users' responses, then calls the calculator. This is the **standalone** engine — not currently exposed via any controller/endpoint (see Part 7, "compatibility-result API" question).

**`scoring/psychology-compatibility.types.ts`** — `PsychologyCompatibilityStatus`, `PsychologyFlagSeverity`, `QuestionCompatibilityBreakdown`, `PsychologyCompatibilityFlag`, `PsychologyCompatibilityResult`.

**`tests/*.spec.ts`** — see Part 16 for what each proves.

### Psychology-related files OUTSIDE the psychology folder

| File | What changed | Why |
|---|---|---|
| `apps/api/src/app.module.ts` | Registered `PsychologyModule` | Makes the 3 HTTP endpoints reachable |
| `apps/api/src/modules/matches/matches.module.ts` | Imports `PsychologyModule`; registers `PsychologyMatchContextService` | Lets Discover scoring read quiz data (one-directional: matches→psychology only) |
| `apps/api/src/modules/matches/scoring/compatibility.service.ts` | Added `PSYCHOLOGY_COMPATIBILITY_SIGNAL` to the signal pipeline; `score()`/`scoreMany()` gained an optional 4th parameter | Part 13 |
| `apps/api/src/modules/matches/scoring/compatibility-signal.ts` | `ScorableProfile` gained optional `psychologyAnswers`; `CompatibilityInput` gained optional `psychologyQuestions` | Part 13 |
| `apps/api/src/modules/matches/scoring/matching-weights.config.ts` | Added `psychology: 15` to `MATCHING_WEIGHTS`, `'psychology'` to `ScoreKey`, bumped `MATCHING_ALGORITHM_VERSION` | Part 13 |
| `apps/api/src/modules/matches/services/feed.service.ts` | Fetches psychology context per request and threads it into `scoreMany()` | Part 14 |

---

## PART 7 — API Documentation

All 3 endpoints: base path `psychology/quiz`, **every route requires** `Authorization: Bearer <Firebase ID token>` (`FirebaseAuthGuard`, applied to the whole controller — see `psychology.controller.ts:25`). Validated by the project's global `ValidationPipe`.

### `GET /psychology/quiz/active`

**Auth:** required. **Body:** none. **Params:** none.

**Success (200):**
```json
{
  "id": "marriage-compat-v1",
  "title": "Marriage Compatibility Quiz",
  "description": "10 scenario-based questions covering the dimensions most predictive of marital strain: ...",
  "version": "1.0",
  "questions": [
    {
      "id": "nenjam-mc-q01-v1",
      "order": 1,
      "dimension": "conflict_style",
      "questionText": "You and your partner disagree about something that matters to you. What's your natural first move?",
      "options": [
        { "key": "A", "label": "I want to talk it through right away, until we reach a resolution", "value": 1 },
        { "key": "B", "label": "I need some time alone to process before I can discuss it calmly", "value": 2 },
        { "key": "C", "label": "I look for a quick middle ground so we can move on", "value": 3 },
        { "key": "D", "label": "I usually let my partner take the lead on resolving it", "value": 4 }
      ]
    }
    /* ... 9 more, in `order` sequence ... */
  ]
}
```
**Never includes:** `scoringType`, `pairRules` — deliberately, on every question, always (server-side, structurally impossible to leak — see the entity class, not just a filter).

**Errors:** `401` no/invalid token. `404` no active quiz configured (shouldn't happen in a correctly-seeded environment, but is a real, handled case).

### `GET /psychology/quiz/me`

**Auth:** required. **Body:** none.

**Success (200):**
```json
{
  "quizId": "marriage-compat-v1",
  "answers": [
    {
      "questionId": "nenjam-mc-q01-v1",
      "dimension": "conflict_style",
      "questionText": "You and your partner disagree about something that matters to you. What's your natural first move?",
      "selectedKey": "C",
      "selectedLabel": "I look for a quick middle ground so we can move on"
    }
    /* ... one entry per answered question ... */
  ],
  "completedAt": "2026-09-24T10:00:00.000Z",
  "updatedAt": "2026-09-24T10:00:00.000Z"
}
```
**Errors:** `401`. `404` if either there's no active quiz, **or** the caller hasn't submitted yet — Flutter cannot distinguish these two cases from the status code alone; treat both as "show the take-quiz entry point."

### `POST /psychology/quiz/submit`

**Auth:** required.

**Request body (exact shape — this is what Flutter must send):**
```json
{
  "quizId": "marriage-compat-v1",
  "answers": [
    { "questionId": "nenjam-mc-q01-v1", "selectedKey": "C" },
    { "questionId": "nenjam-mc-q02-v1", "selectedKey": "B" }
    /* ... exactly one entry per question in the active quiz, all 10 ... */
  ]
}
```
**`quizId` must be exactly the id `GET /psychology/quiz/active` just returned** — not hardcoded, not cached indefinitely, since a future questionnaire replacement will use a different id.

**Success (200):** same shape as `GET /psychology/quiz/me`.

**Error cases (all `400 BadRequestException`, distinguishable only by message text — no error codes exist):**
- `quizId does not match the active quiz (expected "...")` — stale/wrong quiz id
- `The same question was answered more than once.`
- `Unknown question id(s) for this quiz: ...`
- `All 10 questions must be answered. Missing: ...` — partial submission
- `"X" is not a valid option for question "...".` — invalid `selectedKey`

`404` if no active quiz exists at all.

**Retake:** call this endpoint again with the same `quizId` — it upserts, replacing the caller's prior answers for that quiz. There is no separate "update" endpoint.

### What Flutter must NOT send / calculate
- Must **not** invent or guess a `quizId` — always use the one from the most recent `GET /psychology/quiz/active`.
- Must **not** send a Likert `score` (1-5) — the backend does not understand this shape at all; it expects `selectedKey` (one of `A`/`B`/`C`/`D`).
- Must **not** attempt to compute any compatibility score, flag, or dimension breakdown client-side — there is currently **no endpoint that returns a two-user compatibility result at all** (see below).

### Compatibility-result API — current status

**There is no API endpoint today that returns a two-user psychology compatibility result.** `PsychologyCompatibilityService.computeForUsers()` exists and is fully built/tested (Part 9), but it is not wired to any controller or route. The only way psychology compatibility currently reaches an end user is indirectly, as part of `overallCompatibility` in the Discover feed response (Part 13/14) — there is no way to see the per-question breakdown or flags from the API today. If a future screen needs to show "why this score," a new endpoint must be built first — do not assume one exists.

---

## PART 8 — Answer Storage and Validation

Canonical shape, stored in `UserQuizResponse.answers`:
```
{
  "nenjam-mc-q01-v1": "C",
  "nenjam-mc-q02-v1": "B",
  ...
}
```
This is the **only** stored representation of a user's answers anywhere in the system — no separate "result" or score is cached alongside it (Part 4/9 explain why).

Validation, enforced in `PsychologyService.submitAnswers()`, in this exact order:
1. **Active quiz validation** — `requireActiveQuiz()` throws `404` if none exists.
2. **Quiz ID validation** — `dto.quizId !== quiz.id` → `400`.
3. **Duplicate question prevention** — `new Set(submittedIds).size !== submittedIds.length` → `400`.
4. **Unknown question prevention** — any `questionId` not in the active quiz's question set → `400`, lists the offending ids.
5. **Incomplete submission prevention** — any of the quiz's questions missing from the submission → `400`, lists which ones.
6. **Invalid option prevention** — per answer, `selectedKey` checked against that specific question's real option keys → `400` if not found.
7. **Retake / upsert behavior** — `upsertUserResponse` keyed on `(userId, quizId)`: create if absent, overwrite `answers` in place if present. No history of prior answers is kept.

**What happens if a user has no response:** `GET /psychology/quiz/me` → `404`. Inside the matching engine, `PsychologyMatchContextService.loadContext()` treats "no response" identically whether the user never took the quiz *or* only has a response for a now-retired quiz — both simply produce "no row found for `(userId, currentActiveQuizId)`," and the psychology signal becomes inapplicable for that user (Part 9/13).

---

## PART 9 — Psychology Compatibility Engine

**Three distinct concepts — do not conflate them:**

1. **Quiz answer storage** (`PsychologyService`/`PsychologyRepository`) — stores one person's raw answers. Involves no comparison, no score, no second person.
2. **Pairwise psychology compatibility engine** (`calculatePsychologyCompatibility`, `PsychologyCompatibilityService`) — takes **two** people's stored answers and produces a score + flags. Fully standalone, has never depended on and is not depended on by the existing matcher.
3. **Existing overall matchmaking engine** (`CompatibilityService`) — the real thing that ranks Discover. Since this integration, it *calls into* concept 2 as one of several weighted signals (Part 13). It is not the same code, and concept 2 has no knowledge that concept 3 exists.

### How two users are compared (`psychology-compatibility.calculator.ts`)

For each of the 10 questions (processed in `order`):
1. Look up each user's `selectedKey` for that `questionId`. If either is missing → skip this question (`skippedQuestionIds`), never default to a score.
2. **Matrix lookup with pair normalization:** `pairLookupKey(keyA, keyB)` sorts the two keys alphabetically before building the lookup string (`"A|B"`, never a separate `"B|A"` entry) — so score lookup is symmetric/order-independent by construction, not by convention.
3. If the question id or the resulting pair key isn't in `PSYCHOLOGY_COMPATIBILITY_MATRIX` → skip (never silently defaults to 0 or 100 — this is the "unsupported/stale quiz" defense, see below).
4. Record the score in `breakdown`, and separately check that question's own `pairRules` (unmodified, read live) for a matching entry → if found, push a flag.

**10-question aggregation:** `overallScore = Math.round(sum(scores) / breakdown.length)` — average over only the questions that were actually scoreable, **not** always divided by 10. If every question was skipped, `overallScore` is `null` (never `0`, never `NaN` — a null score is structurally distinguishable from a real low score).

**Rounding:** exactly one rounding operation, at the final average step (`Math.round`). No intermediate rounding anywhere.

**Missing-response behavior:** handled one layer up, by `PsychologyCompatibilityService` (the standalone orchestrator) and separately by `PsychologyMatchContextService` (the live-matching orchestrator) — both check "does each user have a response to the CURRENT active quiz" before ever calling the calculator. The calculator itself only handles missing *per-question* answers defensively (shouldn't happen given submit-time validation, but doesn't crash if it does).

**Stale/unsupported quiz behavior:** if the active quiz's questions reference ids the static matrix doesn't cover (i.e., the questionnaire content changed since the matrix was last reviewed/approved), the calculator would skip those questions individually; the standalone service (`PsychologyCompatibilityService`) additionally checks this **before** calling the calculator and returns a dedicated `UNSUPPORTED_QUIZ_VERSION` status rather than a partial/misleading score.

**Deterministic behavior:** the calculator is a pure function — no `Date.now()`, no randomness, no external state read. The same two answer maps + question list always produce byte-for-byte the same result (asserted directly by a test — Part 16).

---

## PART 10 — All 10 Compatibility Matrices (complete, exact)

Source: `backend/apps/api/src/modules/psychology/scoring/compatibility-matrix.data.ts`. These numbers are a reviewed product decision, not derived from any formula — do not recompute or "simplify" them.

**Q1 — conflict_style (MUST_ALIGN).** A=pursue, B=withdraw, C=compromise, D=defer
| | A | B | C | D |
|---|---|---|---|---|
|**A**|95|60|88|75|
|**B**|—|65|85|72|
|**C**|—|—|95|85|
|**D**|—|—|—|60|

**Q2 — financial_philosophy (MUST_ALIGN).** A=full merge, B=bridge, C=separate, D=one-leads
| | A | B | C | D |
|---|---|---|---|---|
|**A**|95|85|40|70|
|**B**|—|90|85|70|
|**C**|—|—|95|70|
|**D**|—|—|—|60|

**Q3 — family_boundaries (MUST_ALIGN).** A=very involved, B=major-events, C=respectful-distance, D=minimal
| | A | B | C | D |
|---|---|---|---|---|
|**A**|95|75|40|15|
|**B**|—|95|85|55|
|**C**|—|—|95|85|
|**D**|—|—|—|95|

**Q4 — career_adaptability (COMPLEMENTARY_TOLERANT).** A=my-career-priority, B=weigh-together, C=stability-priority, D=scale-back
| | A | B | C | D |
|---|---|---|---|---|
|**A**|40|90|85|88|
|**B**|—|85|88|88|
|**C**|—|—|75|80|
|**D**|—|—|—|75|

**Q5 — household_division (MUST_ALIGN).** A=50/50, B=whoever's-better, C=traditional, D=outsource
| | A | B | C | D |
|---|---|---|---|---|
|**A**|95|70|40|70|
|**B**|—|85|70|75|
|**C**|—|—|85|70|
|**D**|—|—|—|85|

**Q6 — emotional_support (COMPLEMENTARY_TOLERANT).** A=just-listen, B=practical-help, C=space-then-support, D=physical-closeness
| | A | B | C | D |
|---|---|---|---|---|
|**A**|90|75|60|85|
|**B**|—|85|60|80|
|**C**|—|—|85|60|
|**D**|—|—|—|90|

**Q7 — personal_space (MUST_ALIGN).** A=high-independence, B=balance, C=high-togetherness, D=depends
| | A | B | C | D |
|---|---|---|---|---|
|**A**|60|88|40|70|
|**B**|—|88|85|80|
|**C**|—|—|60|70|
|**D**|—|—|—|85|

**Q8 — decision_making (COMPLEMENTARY_TOLERANT).** A=share-together, B=I-lead, C=I-follow, D=involve-families
| | A | B | C | D |
|---|---|---|---|---|
|**A**|95|90|90|85|
|**B**|—|40|95|65|
|**C**|—|—|70|65|
|**D**|—|—|—|65|

**Q9 — children (HARD_AXIS).** A=soon+co-parent, B=soon+traditional, C=open, D=don't-want/later
| | A | B | C | D |
|---|---|---|---|---|
|**A**|100|85|60|**0**|
|**B**|—|100|60|**0**|
|**C**|—|—|90|60|
|**D**|—|—|—|100|

**Q10 — life_stage_timeline (MUST_ALIGN).** A=settle-quickly, B=build-career-first, C=travel-first, D=start-family-soon
| | A | B | C | D |
|---|---|---|---|---|
|**A**|95|65|65|90|
|**B**|—|85|85|40|
|**C**|—|—|85|40|
|**D**|—|—|—|95|

### Explicit vs. inferred vs. flag-derived vs. conditional

This distinction was load-bearing **during the review process** that produced these numbers (documented in the project's audit history), but **does not exist anywhere in the shipped code** — `compatibility-matrix.data.ts` stores only final integers, with no per-cell provenance metadata. If you need that historical reasoning (why a specific cell is what it is), it lived in the design-review conversation, not in this file. Do not assume the code can answer "was this cell explicit or inferred" — it cannot; treat every value in the tables above as final and approved.

---

## PART 11 — Flags / Discussion Notes

Every `pairRules` entry, exactly as stored (source: `quiz.seeder.ts`, quoted per-question in Part 3). Summary table:

| Question | Pair | Type | Severity | Fires when |
|---|---|---|---|---|
| Q1 conflict_style | (A,B) | flag | soft | pursue + withdraw |
| Q1 conflict_style | (D,D) | flag | soft | both defer |
| Q2 financial_philosophy | (A,C) | flag | medium | full-merge + fully-separate |
| Q2 financial_philosophy | (D,D) | flag | soft | both want one person to lead |
| Q3 family_boundaries | (A,D) | **dealbreaker** | high | very-involved + minimal |
| Q3 family_boundaries | (A,C) | flag | medium | very-involved + respectful-distance |
| Q4 career_adaptability | (A,A) | flag | medium | both expect to be accommodated |
| Q5 household_division | (A,C) | flag | medium | 50/50 + traditional |
| Q5 household_division | (C,C) | flag | medium | both "traditional" (conditional — see below) |
| Q6 emotional_support | (A,B) | flag | soft | listen vs. fix mismatch |
| Q6 emotional_support | (C,A)/(C,B)/(C,D) | flag | soft (×3) | timing mismatch vs. any immediate-engagement style |
| Q7 personal_space | (A,C) | flag | medium | high-independence + high-togetherness |
| Q7 personal_space | (A,A) | flag | soft | both high-independence (informational) |
| Q7 personal_space | (C,C) | flag | soft | both high-togetherness (informational) |
| Q8 decision_making | (B,B) | flag | medium | both expect to lead |
| Q9 children | (A,D) | **dealbreaker** | **hard** | wants-kids-soon + doesn't-want |
| Q9 children | (B,D) | **dealbreaker** | **hard** | wants-kids-soon + doesn't-want |
| Q9 children | (C,A)/(C,B)/(C,D) | flag | soft (×3) | open + a strong position |
| Q10 life_stage_timeline | (B,D)/(C,D) | flag | medium (×2) | delay-settling + start-family-soon |

Plus one **informational-only** note with no `pairRules` entry at all (generated in code, not data — see Part 12): the Q8-D ↔ Q3 cross-check.

### Score vs. severity — these are separate systems, do not conflate them

- **Score** (0-100, Part 10) is always computed for every answered question, regardless of whether a flag fires.
- **A flag firing does NOT automatically mean the score for that question is low.** Example: Q7 `(A,A)` scores **60** (soft-flag tier) — a real deduction, but far from 0. Q3 `(A,D)` scores **15** (high-severity, close to the bottom but not the absolute floor). Only Q9's two hard/dealbreaker pairs score exactly **0**.
- **`soft`/`medium`/`high` severities never remove a candidate from anything and never cap the overall score** — they are purely informational/discussion labels attached to a flag object.
- **`hard` severity (Q9 only) is the one exception** — it both scores that question 0 *and* triggers the whole-response ≤40% overall ceiling (Part 12). No other severity does this.
- **The informational note (Q8-D↔Q3) has no severity value at all** (`severity` is `undefined`, `source: 'informational'`) — it must never be rendered as if it were a risk level; it is a "these two things are related, read them together" note, nothing more.

---

## PART 12 — Cross-Question Rules

Source: `psychology-compatibility.calculator.ts`, the two blocks after the main per-question loop.

### Q9 HARD_AXIS — the overall ≤40% ceiling
```
hardAxisTriggered = (Q9's own score === 0)     // true only for (A,D) or (B,D)
ceilingApplied    = hardAxisTriggered && overallScore > 40
finalScore        = ceilingApplied ? 40 : overallScore
```
If the two users' Q9 answers are `(A,D)` or `(B,D)`, the overall psychology score is capped at exactly **40**, *regardless of how well the other 9 questions scored* — the ceiling only ever lowers a score, never raises one (if the unclamped average was already ≤40, `ceilingApplied` stays `false` and the real, lower number is kept). This is on top of Q9's own cell already scoring 0 — two separate effects from the same root cause.

### Q10 ↔ Q9 escalation
When Q10's pair is `(B,D)` or `(C,D)` (its own flag fires, `medium` severity) **and** Q9's pair also matched any of its own `pairRules` (soft or hard — i.e., Q9 itself produced a flag for any reason), the Q10 flag's severity is escalated from `medium` to `high` in the returned flag object, and its message gets an appended note ("escalated: the children/timeline question also shows a mismatch"). **This changes only the flag's severity and message text — it never touches any numeric score**, Q10's own cell value or the overall average. If Q9 produced no flag at all (e.g., identical answers), no escalation happens and Q10's flag stays at its base `medium` severity.

### Q8-D ↔ Q3 — informational only
When either user selected Q8's option D ("we should involve our families before deciding") **and** both users answered Q3 (family_boundaries), a standalone informational flag is generated: `{questionId: null, dimension: null, severity: undefined, message: "One or both of you would want to involve your families in major decisions — worth discussing this alongside your expectations about family involvement day-to-day.", source: 'informational'}`. This is **not** stored in any `pairRules` array — it is generated purely in code, every time the condition is met. It never modifies Q8's score, never modifies Q3's score, never introduces a new severity tier, and is never a dealbreaker. Its purpose is purely to point two related-but-separate questions out to whoever reads the result.

---

## PART 13 — Existing Matching Engine (before and after)

### `CompatibilityService` before psychology (unchanged core, still true today)

File: `apps/api/src/modules/matches/scoring/compatibility.service.ts`. Three governing rules (documented in the file's own doc comment, still accurate): (1) it never filters — hard eligibility (blocks, bans, gender, incomplete profiles, declined interests) lives entirely in `filters/eligibility.builder.ts`, evaluated *before* any candidate reaches scoring; (2) an unstated preference is excluded from the denominator, not scored as a failure; (3) both directions (seeker→candidate and candidate→seeker) run the exact same signal code with roles swapped.

**Weights before this feature** (`matching-weights.config.ts`, `v1.2-preference`), summed to exactly 100:
```
age 14, religion 12, community 11, motherTongue 9, location 9,
education 8, profession 7, maritalStatus 6, height 5, lifestyle 4
                                                              (= 85, preference)
profileCompleteness 6, verification 6, activity 3            (= 15, quality)
```
`overall = mutualFit === null ? seekerFit : round(seekerFit*0.6 + mutualFit*0.4)`. `seekerFit`/`mutualFit` each = `round(earned/possible * 100)` over applicable components only.

### What psychology added — exact formula

`MATCHING_ALGORITHM_VERSION` is now `'v1.3-preference-psychology'`. `MATCHING_WEIGHTS` now sums to **115**:
```
(the same 85 preference points) + (the same 15 quality points) + psychology 15 = 115
```
Psychology is registered as a third signal (`PSYCHOLOGY_COMPATIBILITY_SIGNAL`) in `CompatibilityService`'s `SIGNALS` array, alongside `PREFERENCE_COMPATIBILITY_SIGNAL` and `CANDIDATE_QUALITY_SIGNAL`. It contributes **one** component, key `psychology`, weight `15`, computed as `psychologyOverallScore / 100` when applicable.

**The formula is exactly the same weighted-mean formula as before** — psychology did not introduce a new formula, it added one more term to the existing one:
```
total = round( sum(earned_i for applicable i) / sum(weight_i for applicable i) * 100 )
```
When psychology is applicable, `possible` includes its 15; when not, `possible` is exactly the same 100 as before (85+15), so the formula for anyone without psychology data is **byte-for-byte identical** to before this feature existed.

### When psychology is included / skipped

- **Included** only when BOTH the chooser and the candidate have a saved response to the **current active** quiz. Checked once per Discover request (not per candidate pair) via `PsychologyMatchContextService.loadContext(seekerId, candidateIds)`.
- **If only one user completed the quiz:** psychology is inapplicable for every pair involving that seeker (the context short-circuits the moment the *seeker's own* response is missing — see below) — same treatment as an unstated preference, excluded from the denominator, not scored as 0.
- **If neither completed it:** same — inapplicable, excluded.
- **Optimization:** `loadContext` checks the seeker's own response first; if absent, it returns immediately without even querying candidates' responses (since psychology could never be applicable for this seeker regardless). This means the added cost for the overwhelming majority of users today (who haven't taken the quiz) is exactly **two small single-row lookups** per Discover request, not a 200-row batch query.

### Does psychology affect filtering / hard eligibility / progressive fallback?

**No, none of these.** Psychology is a **ranking-only** signal:
- It cannot remove a candidate from the pool — `filters/eligibility.builder.ts` and the progressive-fallback tiers (`recommendation/tier-plan.ts`) are completely untouched by this feature; a candidate who passes those filters is scored, psychology or no psychology.
- It does not change which of the 10 fallback tiers gets used, or their relaxation order.
- It does not change the seeker/mutual preference logic (age, religion, etc.) — those signals run exactly as before, unaware psychology exists.
- It only ever changes the **`overall` score** used to *order* an already-eligible pool, and only for pairs where both sides completed the quiz.

---

## PART 14 — Discover Flow (file-by-file trace)

```
DiscoverController → FeedService.getFeed()          [services/feed.service.ts]
  │
  ├─ RecommendationService.getFeedForUser()          [ProgressiveFallbackStrategy]
  │     → hard filters (eligibility.builder.ts) → preference WHERE →
  │       up to 10 relaxation tiers if empty (tier-plan.ts)
  │     → returns up to 200 eligible candidate rows, unscored
  │
  ├─ toScorable(row) for seeker + each candidate     [scoring/scorable.mapper.ts — UNCHANGED]
  │
  ├─ PsychologyMatchContextService.loadContext(...)  [scoring/psychology/psychology-match-context.service.ts]
  │     → active quiz? seeker's response? (2 lookups, short-circuits if either missing)
  │     → if seeker has one: batch-fetch candidates' responses + quiz questions
  │
  ├─ attach `psychologyAnswers` onto each ScorableProfile (feed.service.ts, inline)
  │
  ├─ CompatibilityService.scoreMany(seeker, pref, candidates, questions)
  │     → PREFERENCE_COMPATIBILITY_SIGNAL + PSYCHOLOGY_COMPATIBILITY_SIGNAL + CANDIDATE_QUALITY_SIGNAL
  │     → per-candidate CompatibilityBreakdown { seekerFit, mutualFit, overall, band, components[] }
  │
  ├─ RankingService.rank(...)                        [UNCHANGED — orders by `overall`/`mutualFit`]
  │
  └─ ProfileFeedMapper.toDtoList(pageRows, scores)    [mappers/profile-feed.mapper.ts]
        → compatibility: { aiMatchPercent: seekerFit, astroMatchPercent: 0,
                            psychologyMatchPercent: 0,   ← STILL HARDCODED, see below
                            overallCompatibility: overall }  ← DOES include psychology now
```

### Can psychology affect...
- **Candidate eligibility?** No (Part 13).
- **Candidate ordering?** Yes — indirectly, via `overallCompatibility`/`overall`, for pairs where both completed the quiz.
- **Displayed percentage?** Only `overallCompatibility`, and only for qualifying pairs. **Not** `psychologyMatchPercent` — that field is still hardcoded to `0` in `profile-feed.mapper.ts:94`, and `isPsychologyCompleted` is still hardcoded to `false` (`profile-feed.mapper.ts:77`). This is a real, important gap for Flutter to know about: today, `overallCompatibility` may reflect psychology while the dedicated psychology badge field does not — do not assume the two are consistent.
- **Filters?** No.
- **Recommendation cards** (the profile-completion "take the psychology quiz" prompt, `profiles/domain/recommendation-cards.ts`)? Unaffected — that card's logic (`quizCount > 0`) was never touched by this feature and still only checks whether *a* response row exists, regardless of content.

---

## PART 15 — Every File Changed

| File | Change | Why | Impact | Side | Phase |
|---|---|---|---|---|---|
| `backend/libs/database/prisma/schema.prisma` | Replaced OCEAN-specific `QuizQuestion`/`UserQuizResponse` fields with generic ones; new `QuestionScoringType` enum | Support the new 10-question format | Schema | Backend | 2 |
| `backend/libs/database/prisma/migrations/20260923140000_marriage_psychology_questionnaire/` (new) | Hand-written migration deleting OCEAN rows, altering columns | Apply the above to the live DB safely | DB | Backend | 2 |
| `backend/libs/database/src/seeders/quiz.seeder.ts` | Full rewrite: 10 marriage questions replacing 20 OCEAN questions | New quiz content | Seed data | Backend | 2 |
| `backend/apps/api/src/modules/psychology/**` (14 files, new) | New module: controller, service, repository, DTO, entities, scoring engine, tests | The whole answer-storage + standalone-scoring feature | Module | Backend | 3–4 |
| `backend/apps/api/src/app.module.ts` | Registered `PsychologyModule` | Makes the API reachable | Wiring | Backend | 3 |
| `backend/apps/api/src/modules/matches/scoring/psychology/psychology-compatibility.signal.ts` (new) | New `CompatibilitySignal` reusing the psychology calculator | Plug psychology into the real matcher | Scoring | Backend | 6 (Option 2) |
| `backend/apps/api/src/modules/matches/scoring/psychology/psychology-match-context.service.ts` (new) | Fetches quiz data for a live request | Supplies the signal above with real data | Scoring | Backend | 6 |
| `backend/apps/api/src/modules/matches/scoring/compatibility.service.ts` | Added the new signal to the pipeline; optional 4th param on `score()`/`scoreMany()` | Integration point | Scoring | Backend | 6 |
| `backend/apps/api/src/modules/matches/scoring/compatibility-signal.ts` | Optional `psychologyAnswers`/`psychologyQuestions` fields | Data plumbing | Types | Backend | 6 |
| `backend/apps/api/src/modules/matches/scoring/matching-weights.config.ts` | New `psychology: 15` weight; version bump | Weighting | Config | Backend | 6 |
| `backend/apps/api/src/modules/matches/services/feed.service.ts` | Fetches psychology context per request, attaches to `ScorableProfile`s | Live wiring | Orchestration | Backend | 6 |
| `backend/apps/api/src/modules/matches/matches.module.ts` | Imports `PsychologyModule`; registers `PsychologyMatchContextService` | DI wiring | Module | Backend | 6 |
| `backend/apps/api/src/modules/psychology/repositories/psychology.repository.ts` | Added `findResponsesForUsers()` batch method | Support live batch scoring | Repository | Backend | 6 |
| `backend/apps/api/src/modules/psychology/psychology.module.ts` | `exports: [PsychologyRepository]` | Let matches read it | Module | Backend | 6 |
| `backend/apps/api/src/modules/matches/tests/compatibility.service.spec.ts` | Updated weight/version assertions, added psychology-signal tests | Keep tests true, add coverage | Tests | Backend | 6 |
| `backend/apps/api/src/modules/matches/tests/__snapshots__/compatibility-golden.spec.ts.snap` | One new always-inapplicable `psychology` component appended per candidate | Reflect the new signal; proves no score/order moved | Tests | Backend | 6 |
| `backend/apps/api/src/modules/matches/tests/psychology-match-context.service.spec.ts` (new) | Tests for the new context service | Coverage | Tests | Backend | 6 |

**Pre-existing, unrelated changes visible in `git status` (NOT part of this feature — do not attribute them to psychology work):** `backend/apps/api/src/modules/verification/tests/verification.service.spec.ts` (modified before this feature's work began), `docs/development/selfie-verification-frontend-handoff.md` (deleted) and `docs/development/face-verification-flutter-handoff.md` (added) — both pre-existing, unrelated to psychology.

---

## PART 16 — Testing & Verification

All numbers below are from the final, actual test run — not estimates.

| Suite | What it proves |
|---|---|
| Psychology module tests (`psychology/tests/*.spec.ts`, 4 files) | Matrix completeness/range/pinned values; calculator per-question scoring, Q9 ceiling, Q10↔Q9 escalation, Q8-D↔Q3 informational note, missing/unsupported-question handling, determinism, pairRules never serialized; service status handling (`NO_ACTIVE_QUIZ`, `*_INCOMPLETE`, `UNSUPPORTED_QUIZ_VERSION`, `COMPLETE`); answer-storage validation (duplicate/unknown/missing/invalid-option rejection) |
| `matches/tests/psychology-match-context.service.spec.ts` (new) | Short-circuits correctly when no quiz/no seeker response; batch-fetches candidates in parallel with questions; correctly maps responses by user id |
| `matches/tests/compatibility.service.spec.ts` | Weight table now sums to 115; 14 components emitted (not 13); psychology inapplicable by default; psychology becomes applicable and scores correctly against the real matrix when data is supplied; algorithm version stamped correctly |
| `matches/tests/compatibility-golden.spec.ts` (12 snapshots) | **Zero change** to any existing score, band, or ranking order for any of the 12 candidate fixtures across 3 seeker-preference scenarios — the only snapshot diff anywhere is one new, always-`applicable: false`, zero-point `psychology` component appended per candidate |
| Full backend suite (`pnpm test` / `npx jest`) | **1,187 tests passing**, 0 failing, 12/12 snapshots passing, across the entire backend — not just the touched modules |
| `tsc --noEmit` | 0 type errors, whole backend |
| `eslint` (scoped to every file this feature touched) | 0 errors |
| `nest build api` + `node scripts/smoke-boot.mjs` | All 4 backend apps (api/worker/scheduler/websocket) boot successfully with the new cross-module DI wiring (`MatchesModule` importing `PsychologyModule`) |
| Migration verification | Live read-only query confirmed 0 real `user_quiz_responses` rows before the destructive migration ran; confirmed the new 10-question content exists and old OCEAN content is gone, after |

**Not done / explicitly out of scope:** no live HTTP end-to-end test with a real Firebase-authenticated session was run (deliberately avoided touching the dummy-OTP dev-auth flow, which is treated as security-sensitive); no Flutter-side test exists for any of this (there is no Flutter implementation yet — Part 17).

---

## PART 17 — Flutter Developer Handoff — Dhatri

### A. Already handled by backend — Flutter does NOT need to build any of this

- Quiz content, storage, retake logic, and all validation (duplicate/unknown/missing/invalid-option rejection) — fully server-side.
- Scoring, flags, cross-question rules, the Q9 ceiling — fully server-side, and **must never be reimplemented client-side** (Part 19).
- Psychology's contribution to the real Discover match score — already live, requires zero frontend work to "activate" (it activates automatically the moment two users have both submitted).

### B. Flutter work remaining — inspected against the actual current code

I read every file in `lib/features/psychology/` plus the router, endpoints file, and discover-feed models before writing this. Here is the exact current state, verified, not assumed:

| Item | Current state (verified) |
|---|---|
| Psychology quiz entry point | **Exists, reachable** — route `/registration/psychology-quiz` registered in `app_router.dart:428-432`, linked from 4 screens (profile intelligence hub, profile completion card, edit-profile flow, profile review page). But it opens the **old** quiz UI (see below) — needs to be replaced, not built from scratch. |
| Fetch active quiz | `lib/features/psychology/data/repositories/api_personality_repository.dart` exists and calls the right URL (`ApiEndpoints.psychologyQuizActive = '/psychology/quiz/active'`, `lib/core/network/api_endpoints.dart:77`) — but its response parsing expects an OCEAN-shaped question (`oceanDomain` field), not the new `dimension`/`options` shape. **Needs a rewrite of the model + parsing, not just re-wiring.** |
| Display 10 questions | `psychology_quiz_page.dart` renders one Likert (1-5, "Strongly Disagree"→"Strongly Agree") question per screen — hardcoded, unrelated to the new multiple-choice-with-4-labeled-options format. **Needs a new question-rendering widget** (4 tappable option cards showing each option's real label text, not a Likert scale). |
| Option selection | No concept of "selected key" exists anywhere in the current models (`quiz_question.dart` has no options list at all). **New models needed.** |
| Local answer state | `personality_provider.dart` has a `PersonalityQuizNotifier` holding `Map<String, int>` (question→Likert score). **Needs to become `Map<String, String>` (question→selectedKey).** |
| Submit answers | `ApiPersonalityRepository.submitPersonalityQuiz()` sends `{quizId, answers: [{questionId, score}]}` (`score` is an int) — **does not match** the real backend contract `{quizId, answers: [{questionId, selectedKey}]}`. **Must be rewritten.** |
| Loading states | Present in the existing page (`QuizPhase.intro/question/result`) — the state-machine skeleton is reusable, only the content per phase needs replacing. |
| Validation/error states | Not present in any meaningful way today — the old page assumes every call succeeds. **New error handling needed** for every documented `400`/`404` case (Part 7). |
| Submission success | Old `_ResultView` renders OCEAN trait bars (`PsychologySection`) — **not applicable** to the new response shape at all. Needs a new result view (see UX recommendations, Part 18). |
| Existing response retrieval | `GET /psychology/quiz/me` — no current Flutter code calls this endpoint with a parser matching its real shape (the old repo doesn't even attempt to call `psychologyQuizMe`). **Needs to be built.** |
| Retake behavior | No current UI concept of "you already answered, want to retake?" — **needs to be built** (e.g., pre-fill answers from `GET /me`, or offer a "retake" entry point). |
| Psychology result screen (self) | Old `_ResultView` is OCEAN-shaped and not reusable. **New screen needed.** Note: there is no per-question/dimension *comparison* result available from any API today (Part 7) — a self-only "here's what I answered" screen is all that's currently supportable. |
| Per-question/dimension breakdown (two-user comparison) | **No such API exists yet** (Part 7) — do not build UI for this until a backend endpoint is added. |
| Discussion flags UI | **No such API exists yet** for the same reason. |
| Handling incomplete quiz | Not built — needs a state for "you haven't answered all 10 yet, X remaining." |
| Handling backend errors | Not built — needs mapping of the 5 documented `400` messages (Part 7) to user-facing copy. |
| Handling unsupported/stale quiz version | Partially relevant only if `GET /active` 404s (no quiz configured) — straightforward to handle as an empty/disabled state. |
| Discover integration | `CompatibilityEntity`/`DiscoveryProfileModel` already parse `psychologyMatchPercent` from the feed response (`lib/features/discover/data/models/discovery_profile_model.dart:70-71`) — but **no widget renders it** (`compatibility_badge.dart` only renders `aiMatchPercent`/`astroMatchPercent`). Given the backend still sends `psychologyMatchPercent: 0` always (Part 14), there is nothing meaningful to display yet — leave this as-is until backend exposes a real per-user psychology contribution. |
| Profile/completion UI affected by psychology | The "Psychology" completion card (`profile_completion` feature, tested in `complete_profile_card_test.dart` and siblings) already links to the quiz route and reacts to a `psychologyComplete` flag — this plumbing is fine and doesn't need to change; it just needs the quiz *destination* it links to to be rebuilt. |

### What must be built, concretely, per item

**1. New models** (replace `lib/features/psychology/domain/models/quiz_question.dart` and `personality_result.dart`):
```dart
class QuizOption {
  final String key;      // "A" | "B" | "C" | "D"
  final String label;
  final int value;
}
class QuizQuestion {
  final String id;
  final int order;
  final String dimension;
  final String questionText;
  final List<QuizOption> options;
}
class MarriageCompatQuiz {
  final String id;
  final String title;
  final String? description;
  final String version;
  final List<QuizQuestion> questions;
}
class QuizAnswer {
  final String questionId;
  final String dimension;
  final String questionText;
  final String selectedKey;
  final String selectedLabel;
}
class MyQuizResponse {
  final String quizId;
  final List<QuizAnswer> answers;
  final DateTime completedAt;
  final DateTime updatedAt;
}
```
Field names above are suggestions to match the API response shape exactly (Part 7) — parse directly from JSON, no renaming needed.

**2. New/rewritten repository** (replace `api_personality_repository.dart`):
- `Future<MarriageCompatQuiz> getActiveQuiz()` → `GET psychologyQuizActive`
- `Future<MyQuizResponse?> getMyResponse()` → `GET psychologyQuizMe`, return `null` on 404 rather than throwing (so the UI can show "not taken yet" cleanly)
- `Future<MyQuizResponse> submit(String quizId, Map<String, String> answers)` → `POST psychologyQuizSubmit` with body exactly `{quizId, answers: answers.entries.map((e) => {'questionId': e.key, 'selectedKey': e.value}).toList()}`

**3. Wire the real repository** — `personalityRepositoryProvider` (`personality_provider.dart:11-13`) is currently hardwired to `MockPersonalityRepository()`. This must change to the new API repository once it's rewritten — confirmed via repo-wide search that **no override exists anywhere today**, so this is a direct edit, not an override to add.

**4. New question UI** — one screen per question (or a paged flow), rendering the 4 real option labels as tappable choices, storing `selectedKey` in local state, requiring all 10 before enabling submit.

**5. Result/completion screen** — show the user their own answers back (from `GET /me` or the `submit` response) — there is no compatibility score to show here (that's pairwise, not computable from one person's answers — Part 9).

### C. What Flutter must NEVER implement

- **Never compute a compatibility score client-side.** There is no formula Flutter could correctly reproduce — the approved matrix (Part 10), the Q9 ceiling, and the cross-question rules (Part 12) are intentionally server-only.
- **Never request or expect `pairRules` from any endpoint.** It is structurally excluded from every response (Part 7) — if you ever see it, something is wrong.
- **Never hardcode question content.** Always fetch from `GET /psychology/quiz/active` — the questions can change without a Flutter release if a future quiz version is seeded.
- **Never assume `quizId` is always `"marriage-compat-v1"`.** Always use whatever `GET /active` returns.
- **Never send a Likert `score`.** The backend has no code path that understands that shape anymore.

### Copy-paste reference: submit request/response

**Request:**
```json
POST /psychology/quiz/submit
Authorization: Bearer <firebase-id-token>
Content-Type: application/json

{
  "quizId": "marriage-compat-v1",
  "answers": [
    { "questionId": "nenjam-mc-q01-v1", "selectedKey": "C" },
    { "questionId": "nenjam-mc-q02-v1", "selectedKey": "B" },
    { "questionId": "nenjam-mc-q03-v1", "selectedKey": "C" },
    { "questionId": "nenjam-mc-q04-v1", "selectedKey": "B" },
    { "questionId": "nenjam-mc-q05-v1", "selectedKey": "B" },
    { "questionId": "nenjam-mc-q06-v1", "selectedKey": "A" },
    { "questionId": "nenjam-mc-q07-v1", "selectedKey": "B" },
    { "questionId": "nenjam-mc-q08-v1", "selectedKey": "A" },
    { "questionId": "nenjam-mc-q09-v1", "selectedKey": "A" },
    { "questionId": "nenjam-mc-q10-v1", "selectedKey": "A" }
  ]
}
```
**Response (200):** see the `GET /me` example in Part 7 — identical shape.

**Error (400) example:**
```json
{
  "statusCode": 400,
  "message": "All 10 questions must be answered. Missing: nenjam-mc-q09-v1, nenjam-mc-q10-v1",
  "error": "Bad Request"
}
```

---

## PART 18 — Frontend UX Recommendations

Suggested flow, consistent with what the backend actually supports today:
```
Profile / Profile Intelligence hub
   → "Take Psychology Quiz" (existing entry points, just re-point them)
   → 10 questions, one at a time, all optional to leave and resume later
       (no partial-save exists server-side, so keep answers in local state
        until the final submit — don't call the API per-question)
   → Submit (all 10 required)
   → Completion screen: show the user their own answers back, framed as
     "here's what you shared" — not a score, not a comparison
   → Return to profile / Discover
```
- **Presenting the score:** there is currently no per-user-pair score to present in the UI (Part 7/14) — don't build a "your compatibility with X" screen yet.
- **Discussion flags / serious mismatches:** same — no API exposes these to a specific pair today. When/if that endpoint is built, the recommendation is to always show a hard/dealbreaker item (like a children mismatch) as a clearly separate, plainly-labeled banner — never blended into or implied by a percentage (this matches how the backend itself treats the distinction, Part 11).
- **Incomplete state:** show a clear "X of 10 answered" rather than a generic error if the user backs out mid-quiz.
- Do not make any clinical, psychological, or "this predicts your marriage" claim anywhere in copy — this quiz measures alignment on specific questions, nothing more (Part 1).

---

## PART 19 — Security / Trust

- **Authentication:** every psychology endpoint requires a real, Firebase-verified `Authorization: Bearer` token (`FirebaseAuthGuard`, applied controller-wide) — no unauthenticated access exists.
- **Server-side validation:** every rule in Part 8 is enforced in `PsychologyService`, not merely suggested by the DTO — a malformed request is rejected before it ever reaches storage.
- **`pairRules` is server-only, structurally.** It is excluded at the entity-mapping layer (`toQuestionEntity()` only copies `options`, never `pairRules`) — not filtered defensively at the controller, but simply never read into the response object in the first place.
- **Why scoring stays backend-side:** the approved matrix and cross-question rules are the actual intellectual content of this feature — shipping them to a client would both leak them and remove any ability to correct/version them without an app release. Flutter must never receive or compute scoring logic (Part 17C).
- **Sensitive data considerations:** answers are personal relationship-expectation data; they are only ever returned to the answering user themselves (`GET /me`) — there is currently no endpoint that returns another user's raw answers or a pairwise result to either party (Part 7), which is itself a privacy-conservative current state, not an oversight to "fix" casually.
- **No secrets in Flutter:** nothing in this feature requires any credential, API key, or secret on the client side — only the Firebase ID token already used elsewhere in the app.
- **Subscription/premium relationship:** psychology is **not currently gated behind any subscription tier** anywhere in the backend — no premium check exists in `PsychologyController`/`PsychologyService`. If this changes in future, it would need an explicit, separate implementation; nothing here should be assumed either way beyond what's stated.

---

## PART 20 — Current Limitations

**What is complete:** quiz content, storage, validation, retake; the full pairwise scoring engine (matrix, flags, cross-question rules, Q9 ceiling); live integration into the real Discover match score, proven not to disturb existing behavior (Part 16).

**What Flutter still needs (all of it — see Part 17):** every screen, model, and repository call for the new question/answer shape. The existing Flutter psychology feature is 100% built for the retired OCEAN quiz and is not reusable beyond its page-flow skeleton and route registration.

**Not E2E tested:** no real HTTP round-trip through a live Firebase-authenticated session has been exercised (Part 16) — all verification is unit/integration-level against mocked or direct-Prisma data.

**Known gaps:**
- No API exposes a two-user psychology compatibility result (score + flags) to any client — `PsychologyCompatibilityService` is fully built but unwired to any controller.
- `psychologyMatchPercent`/`isPsychologyCompleted` in the Discover feed response are still hardcoded (`0`/`false`) — `overallCompatibility` reflects psychology, these dedicated fields do not (Part 13/14).
- No outcome/effectiveness tracking exists (does psychology alignment actually correlate with more mutual interest, more conversation, etc.) — there is no infrastructure anywhere in the codebase for this today.
- Q5's `(C,C)` pairRule is explicitly noted (Part 3/11) as conditional on a follow-up sub-question that doesn't exist — it currently fires unconditionally.

**Do not casually change:** the approved matrix values (Part 10), the question ids (`nenjam-mc-q0X-v1`), or the `pairRules` content — see Part 21.

---

## PART 21 — Future Integration / Maintenance Rules

- **Do not modify scoring matrices without updating tests/specification.** `compatibility-matrix.data.spec.ts` pins the four values that were revised during the original review and asserts full 10×10-pair coverage per question — a matrix edit that isn't matched by an intentional test update is exactly the failure mode that test suite exists to catch.
- **Do not change question IDs casually.** They are the join key between `QuizQuestion`, `UserQuizResponse.answers`, and `PSYCHOLOGY_COMPATIBILITY_MATRIX` — changing one without the other two silently breaks scoring (the calculator would simply skip the question rather than erroring loudly).
- **Do not expose `pairRules` to any client**, ever, under any new endpoint — this is a repeated, explicit product requirement across this feature's entire build process.
- **Do not move scoring to Flutter.** The server-only design is deliberate (Part 19), not an artifact of "not having gotten to it yet."
- **Do not modify `CompatibilityService` without regression tests.** The golden-master snapshot (`compatibility-golden.spec.ts`) exists specifically to catch an unintended change to existing (non-psychology) matching behavior — treat any diff in it as a bug to investigate, not a snapshot to blindly update (this document's own Part 15/16 change was verified line-by-line before accepting, not blindly regenerated).
- **Do not change the Q9 hard-axis rule (children dealbreaker, ≤40% ceiling) without explicit product approval** — it is the one place this feature makes a strong, opinionated claim, and it was deliberately reviewed and approved as such.
- **Keep psychology scoring deterministic.** `calculatePsychologyCompatibility` must never be given a reason to read the clock, randomness, or any external state — this is asserted directly by a test and is core to why the feature is explainable at all.
- **Keep psychology separate from unrelated matching logic.** The one-directional dependency (matches→psychology, never the reverse) should be preserved in any future change — psychology should never need to know matching exists.
- **Preserve backward compatibility where possible.** A future new questionnaire version should be a new `PsychologyQuiz` row with a new id (the schema was explicitly designed for this, Part 4), not a mutation of the current one.

---

## PART 22 — Quick Reference

### Backend
- **Module:** `backend/apps/api/src/modules/psychology/`
- **Key services:** `PsychologyService` (storage/validation), `PsychologyCompatibilityService` (standalone pairwise engine, unwired to any endpoint), `calculatePsychologyCompatibility()` (pure scoring function, reused by both the standalone engine and live matching)
- **APIs:** `GET /psychology/quiz/active`, `GET /psychology/quiz/me`, `POST /psychology/quiz/submit` — all Firebase-auth-guarded
- **Schema:** `PsychologyQuiz` / `QuizQuestion` (dimension, scoringType, options, pairRules) / `UserQuizResponse` (answers is canonical)
- **Scoring engine:** `psychology/scoring/compatibility-matrix.data.ts` (100 approved numbers) + `psychology-compatibility.calculator.ts` (pure function)
- **Matcher integration:** `matches/scoring/psychology/` (signal + context service), weight `15` of `115` total, `matching-weights.config.ts`

### Flutter
- **What to build:** new models, new repository (real API, not mock), new question/answer UI, new result view — full list in Part 17B
- **APIs to call:** the 3 above, exact request/response shapes in Part 7/17
- **What not to calculate:** any score, any flag, any matrix lookup — server-only, always

### Matching
- **Psychology contribution:** 15 of 115 total weight points, only when both users completed the current active quiz
- **Conditions:** ranking-only, never affects hard filters/eligibility/progressive fallback
- **Score flow:** per-question matrix score → average → Q9 ≤40% ceiling if triggered → one weighted component in `CompatibilityService` → `overallCompatibility` in the Discover API response

### Testing
- **Final status:** 1,187/1,187 backend tests passing, 12/12 snapshots passing (golden master unchanged in substance), 0 TypeScript errors, 0 lint errors on touched files, all 4 backend apps boot cleanly
