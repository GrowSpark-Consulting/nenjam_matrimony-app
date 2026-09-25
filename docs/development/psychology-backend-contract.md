# Psychology (Marriage Compatibility Quiz) — Current Backend Contract

**Date:** 2026-09-25 · **Supersedes** the matching, storage and API-behaviour parts of
[psychology-matchmaking-handoff.md](psychology-matchmaking-handoff.md) wherever they
disagree (its Parts 2, 6, 7, 8, 13, 14, 16, 17, 20 and 22 describe an earlier design —
"115 total weight", "upsert", scores that include psychology). The quiz *content*,
question text, matrices (Part 10) and flag rules (Parts 11–12) are unchanged.

This is written for whoever builds the Flutter side. **Nothing here needs a Flutter
change to keep working**, but items marked **⚠ client-visible** change what the API
returns and the app should handle them.

---

## 1. The one rule

**Psychology is an optional refinement of ranking. It is never a dependency.**
If anything about it fails — database, timeout, malformed data, a bug — Discover ranks
without it and returns the normal feed. A member who did not take the quiz is never
scored lower for that.

## 2. How it affects Discover (this replaced the "15 of 115" model)

- The weighted matching model is **exactly 100 points again** and contains **no
  psychology term**. Every number a member can see (`aiMatchPercent`,
  `overallCompatibility`, the band, matched/unmatched preferences) is identical whether
  or not either member took the quiz.
- Psychology only nudges **order**. When *both* members have a current, complete answer
  set, the pair gets a small ranking adjustment (`PSYCHOLOGY_REFINEMENT` in
  `matching-weights.config.ts`):
  - **0 to +6** points for a strong pair (quiz score above 60, linear to +6 at 100);
  - **exactly 0** for an average or weak pair — never negative;
  - **−10** only for a declared hard-axis conflict (the children question's dealbreaker
    pair) between two members who both answered.
- Neither took it / only one took it / data stale, malformed or unavailable / any
  failure ⇒ adjustment **0** ⇒ ranking key equals the visible score.
- The adjustment is bounded, so it cannot overtake a candidate more than 16 base points
  ahead, and it cannot dominate the model.
- `psychologyMatchPercent` stays `0` and `isPsychologyCompleted` stays `false` **by
  design** now: exposing either (or any psychology-derived number) would let one member
  read another's answers back out by re-answering and watching it move. Do not build UI
  that expects them, and do not ask backend to populate them without a privacy review.

## 3. Endpoints

`GET /psychology/quiz/active` — unchanged.

`GET /psychology/quiz/me` ⚠ **client-visible** — `404` now also means *"your saved answers
no longer apply"* (a question was added, an option key changed, or the quiz version moved
on), not only "never taken". Treat 404 as "show the quiz".

`POST /psychology/quiz/submit` ⚠ **client-visible**

| Situation | Result |
|---|---|
| First submission | `200`, saved |
| Same answers again (double tap, retry) | `200`, nothing changes |
| Different answers, cooldown active | **`429`** `{ statusCode, error, message, retryAfterSeconds }` |
| Different answers, cooldown passed | `200`, saved, cooldown restarts |
| Your saved answers are stale (quiz updated) | `200`, saved — **never** delayed by the cooldown |
| Validation failure | `400` (as before) |
| Server-side save failure | `500` with a generic message (never contains your answers) |

The retake cooldown is `PSYCHOLOGY_RETAKE_COOLDOWN_DAYS` (default **7**, `0` disables).
It exists because a member's answers order *other members'* feeds; unlimited
re-answering would let someone infer a specific member's answers from how their own feed
reorders. Suggested UI: if the member already has answers, pre-fill from `GET /me`, and
explain the wait when `429` returns (`retryAfterSeconds` is authoritative).

Request bounds: `answers` 1–50 items; `questionId` ≤ 100 chars; `selectedKey` ≤ 20 chars;
`quizId` non-empty ≤ 100 chars.

## 4. Feed cursor ⚠ client-visible (only for in-flight cursors)

`nextCursor` is now sealed (AES-256-GCM) and bound to the member it was issued to. The
client must keep treating it as an opaque string (it already should). A cursor from
before this change, a tampered one, or another member's is ignored and the feed starts
from the first page — so a member paging during the deploy may once see page 1 again.

Why: the cursor carries the ranking key, which includes the psychology adjustment.
A readable or forgeable cursor would leak it.

## 5. Feed invalidation

Submitting or changing answers emits the existing `feed.invalidate` event with reason
`psychology_updated` (an unchanged resubmission emits nothing). The client already
refetches on this event and does not branch on the reason.

## 6. Data model / integrity (migration `20260925120000_psychology_integrity_hardening`)

Additive only — no rows are updated or deleted, no column is dropped:

- unique `(quiz_id, order)` and `(quiz_id, dimension)` on `quiz_questions`;
- at most **one active quiz** (partial unique index);
- `user_quiz_responses.quiz_version` (nullable; `NULL` = current, so existing answers stay
  valid). Bumping a quiz's `version` invalidates its existing responses without a new
  quiz id;
- deleting a quiz that has responses is refused (`ON DELETE RESTRICT`); deleting a *user*
  still cascades to their answers;
- `CHECK` (added `NOT VALID`, so legacy rows are never rechecked) that `answers` is a JSON
  object and `options` / `pair_rules` are JSON arrays.

Content rule: **never edit a released question's option keys, meaning or scoring in
place.** Change what a question asks by adding a new question id (plus matrix entry) or a
new quiz id. A CI test (`psychology-content-integrity.spec.ts`) pins this.

## 7. Operations

- `pnpm seed:quiz` seeds only the quiz (do **not** use `pnpm db:seed` for this: it also
  runs the default-admin seeder). Idempotent; never re-activates a retired quiz.
- `PSYCHOLOGY_MATCHING_ENABLED=false` is a kill switch: no psychology queries, ranking
  identical to pre-psychology. `PSYCHOLOGY_TIMEOUT_MS` (default 800) bounds each lookup.
- A circuit breaker pauses psychology queries after 3 consecutive failures for 30 s.
- Failures log a throttled warning (≤ 1/min per kind) with the error class/code only —
  database error messages can embed a member's answers, so they are never logged.
- Before deploying the migration to a hand-edited database, run the precondition queries at
  the top of the migration file.

## 8. Not exposed, ever

Per-question breakdowns, flags, pair-rule messages, the ranking key, the refinement, or
any member's answers except the caller's own (`GET /me`). The standalone pairwise
service that could produce flags was removed as dead code; a future "why this score"
feature needs a privacy review first.
