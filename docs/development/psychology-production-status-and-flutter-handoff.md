# Psychology — Production Status & Flutter Handoff

**Written:** 2026-09-25
**Sources of truth:** the final backend implementation and audit reports (Part A); the Flutter code on `origin/main` at commit `2d00b0d` (Part B). Nothing in this document is speculation: where something could not be verified, it says so.

> **Read this first — repository state.**
> 1. The redesigned backend described in Part A is **implemented and verified, but uncommitted** in the working tree. Until it is merged and deployed, any environment running `origin/main` still has the *earlier* Psychology integration (the 115-point model and an unguarded Discover path).
> 2. The working tree used to produce this document is **two commits behind `origin/main`**. Those commits (`2d00b0d` and the PR #89 schema fix) contain the Flutter Psychology integration. Part B therefore reads the Flutter code from `origin/main` (via `git show`), not from the local files, and no Flutter file was modified.
> 3. The backend schema change in this work already includes the same one-line schema fix as PR #89, so the two should merge cleanly.

This document supersedes the matching / API-behaviour parts of
[psychology-matchmaking-handoff.md](psychology-matchmaking-handoff.md). A shorter API-only summary lives in
[psychology-backend-contract.md](psychology-backend-contract.md); if they ever disagree, this document is newer.

**Contents**
- [PART A — Current production status](#part-a--psychology-current-production-status)
- [PART B — Flutter handoff](#part-b--flutter-psychology-handoff)
- [Flutter implementation checklist](#flutter-implementation-checklist)
- [Backend ↔ Flutter contract summary](#backend--flutter-contract-summary)

---

# PART A — PSYCHOLOGY: CURRENT PRODUCTION STATUS

## A1. Executive summary

Psychology is the **Marriage Compatibility Quiz**: ten short, everyday-life scenario questions. Two members who both complete it get a small nudge in how they are *ordered* in each other's Discover feed. That is all it does.

**Where it stands.** The backend is complete and, in verification, production-grade: no known backend Psychology bug, security/privacy gap, or data-integrity issue remains open. It is built so that:

- **It is optional and never a dependency.** If Psychology fails for any reason, Discover returns the normal feed.
- **Not taking it never costs anyone anything.** A member who skipped the quiz keeps exactly the matching score they would have had if the feature did not exist.
- **The matching model is back to exactly 100 points.** Psychology is not part of it (this replaced an earlier "115" design).
- **Nothing about Psychology is shown to other members** — no score, no answers, no badge.

**What is not done.**
1. The backend changes are uncommitted and not yet deployed (see the repository-state note above).
2. The **Flutter app has real gaps** (Part B). The most serious: the app does not understand the new 7-day retake wait, and a search filter labelled "Completed Profile" currently hides *every* member because it is wired to a Psychology flag the backend never sets.
3. A few known limitations remain (section A18).

**Readiness in one line:** ready to deploy behind the on/off switch; the feature is not fully working end-to-end for members until the Flutter items in Part B are done.

---

## A2. The complete feature flow, in plain language

1. **A member opens the quiz** (from Profile, the profile-completion card, or the profile review screen). The app first asks the server whether they already have saved answers.
2. **First time:** they see a short introduction, then press *Start Quiz*.
3. **Ten questions**, one per screen, each with four options. They pick one option per question and move forward.
4. **They submit** on the last question. The server checks the answers and saves them.
5. **They see a completed screen** listing their own answers, with a *Retake* option.
6. **Behind the scenes**, their Discover feed is told to refresh, because their ordering may now change.
7. **Other members never see any of this.** When a member who took the quiz appears in someone else's Discover, nothing on the card says so.
8. **Ordering:** when *both* the viewer and the profile shown have valid answers, the profile may move slightly up (a good fit) or, only for a stated disagreement about having children, down. Otherwise nothing changes.
9. **Retaking** is allowed, with a waiting period (default 7 days) between *changes*.

---

## A3. How the quiz works

- **One active quiz** at a time (currently *Marriage Compatibility Quiz*, id `marriage-compat-v1`, version `1.0`).
- **Ten questions**, each single-choice with four options (A–D). The topics are: how you handle conflict, money, family/in-law involvement, career flexibility, sharing household work, emotional support, personal space, how decisions get made, children, and the first years of marriage.
- The questions and options come from the server; the app never hardcodes them, so the quiz can be updated without an app release.
- The quiz is **optional**. Nothing in registration, Discover, chat or matching requires it.
- The quiz **content is frozen once released.** Changing what a question asks or its options means a new question or a new quiz version — never a quiet edit. A test in the backend fails if someone edits released content in place.

## A4. How submission works

- The app sends the quiz id and one chosen option per question. **All ten must be answered**; the server rejects anything missing, duplicated, unknown or invalid (HTTP 400).
- The answers are stored as the member's single saved response, tagged with the quiz version they were given against.
- **Same answers again** (for example a double-tap or a retry): treated as a success and changes nothing.
- **First submission:** always accepted immediately.
- **Answers that no longer fit the quiz** (a question was added, an option changed, the version moved on, or the saved data is damaged): the server treats them as *"not taken"* — the member is simply asked to retake, and is **never made to wait** for that retake.
- **Two submissions at the same moment** are settled by the database, so a member can never end up with two saved responses, and a double-tap never produces an error.
- **If saving fails** for a technical reason, the member gets a generic "please try again" — never a message that could contain their answers. Logs record only the kind of error, never the content.

## A5. How retakes work

| Situation | Result |
|---|---|
| Member has never taken it | Allowed |
| Submits the **same** answers again | Success, nothing changes |
| Submits **different** answers within the waiting period | **Blocked** — HTTP 429 with a message and `retryAfterSeconds` |
| Submits different answers after the waiting period | Allowed; the waiting period restarts |
| Their saved answers are **stale** (quiz was updated) | Allowed immediately; **no** waiting period |

- Default waiting period: **7 days** (`PSYCHOLOGY_RETAKE_COOLDOWN_DAYS`; `0` switches it off).
- **Why it exists:** a member's answers influence *other members'* feeds. If someone could re-answer freely, they could watch how their own feed reorders and gradually work out a specific person's answers. The wait makes that impractical.
- The wait is enforced atomically inside the database update, so several simultaneous retakes cannot all slip through.
- The waiting period is counted from when the current answers were completed.

## A6. How Psychology compatibility is calculated (simple terms)

Only when **both** members have a complete, current set of answers:

1. For each of the ten questions, the two members' chosen options are looked up in a **pre-approved table** that rates every possible pairing from 0 to 100. Sharing the same view usually scores high; some pairings score low (for example, one wants full financial merging and the other wants totally separate finances).
2. The ten ratings are **averaged** into one number from 0 to 100.
3. **Children rule (Q9):** if one member wants children soon and the other does not want children or wants to decide much later, that is a *dealbreaker pairing*. The overall number is then capped at 40.
4. Some pairings also produce private "discussion notes" (for example, "agree on a pause-and-return rule for disagreements"). **These are computed by the engine's tests but are never shown to anyone and never used in Discover.**

A pair that cannot be scored on **every** question (someone's answers are incomplete, out of date, or damaged) is **not scored at all** — it never produces a partial number.

The result is the same whichever member is "the viewer".

## A7. How Psychology interacts with the existing 100-point matching system

**The existing model is untouched and is the foundation.** It scores how well a candidate fits the viewer's stated partner preferences (age, religion, community, mother tongue, location, education, profession, marital status, height, lifestyle) plus three candidate-quality factors (profile completeness, verification, recent activity), on a 100-point scale, blended 60/40 with how well the viewer fits the candidate's preferences.

Psychology is **not part of that score**. It adds a small, separate adjustment used **only to break ties and refine order** in Discover:

| Situation | Adjustment to ordering |
|---|---|
| Either member hasn't taken it / answers stale or damaged / anything fails | **0** |
| Both took it; the pair is average or weak (score ≤ 60) | **0** (never negative) |
| Both took it; the pair is strong (score above 60) | **+0 up to +6** (rising to +6 at a perfect 100) |
| Both took it; **hard-axis conflict** (Q9 dealbreaker pairing) | **−10** |

- The adjustment is small on purpose: a profile that is more than **16 points** ahead on the normal score can never be overtaken by Psychology alone.
- Every number a member can see — the match percentage, its label, the band — is **identical with or without Psychology**, even when both members took the quiz.
- Psychology never **removes** anyone from Discover. It only affects order.

## A8. The 100 → 115 problem, and how it was resolved

**What went wrong.** The first integration added Psychology as an extra component worth 15 points, taking the possible total to 115. In this kind of average-based score, adding a component changes the maths for *everyone it applies to*, and it only applied to pairs where both members took the quiz. Two measured consequences:

- A typical pair scores about 66 on the quiz, which is *lower* than the high preference-match scores common in a filtered feed. Adding it **pulled a member's score down** — so taking the quiz could *hurt* their ranking against someone who skipped it.
- For a member with few stated preferences, Psychology became **half of their whole score**.

**How it was fixed.**

- Psychology was **removed from the weighted model entirely**. Total weight is exactly **100** again and there are 13 scoring components again, exactly as before Psychology existed.
- Psychology is now a **separate, capped ordering adjustment** (table in A7) that never enters the score's arithmetic.
- **Proof it is byte-for-byte the old behaviour:** the "golden" regression file that records the exact scores and orderings for a fixed set of test members is now **identical to its pre-Psychology contents** (a git comparison against the commit before Psychology shows no difference), and it passes unchanged.
- The algorithm version stamp is `v1.3-psychology-refinement`.

## A9. Not taking Psychology never reduces a member's matching score — explicitly

This is a hard product rule and it is enforced and tested:

- A member without valid Psychology data has **no Psychology term of any kind** — not a zero, not a missing-points penalty, not a lower denominator.
- Their **visible score** is exactly what it would be if Psychology did not exist.
- Their **ordering** is unchanged by the absence of data. (Another member with a *strong* pair may be nudged slightly above them; that is a bonus for the other member, not a penalty to them.)
- The **only** situation in which taking the quiz lowers a pair's ordering is a **declared hard-axis conflict** — two members who both answered and stated opposite positions on having children. That is never applied to anyone who did not take the quiz. (If this is ever judged to conflict with the product rule, setting the penalty to 0 is a one-line configuration change.)
- Profile-completion is also unaffected: the completion percentage has **no Psychology weight** (verified in the backend). Psychology appears there only as an optional suggestion card.

Tests cover, explicitly: neither took it; only the viewer took it; only the candidate took it; both took it; and data unavailable or failing.

## A10. How Psychology affects Discover ordering

1. Discover builds the candidate list exactly as before (eligibility, blocks, preferences, fallback tiers — all unchanged).
2. It scores each candidate with the 100-point model.
3. For candidates where **both** members have valid quiz answers, it adds the small adjustment (A7) to an internal *ordering* number.
4. It sorts by that ordering number (ties broken exactly as before), demotes recently-seen profiles exactly as before, and returns the page.

Ordering inputs are never returned to the app. The "next page" pointer is now sealed (see A13).

## A11. What happens with one, both or neither member having data

| Viewer took it | Candidate took it | Effect |
|---|---|---|
| No | No | None. Normal score and order. |
| Yes | No | None. Normal score and order for that candidate. |
| No | Yes | None. |
| Yes | Yes (both current & complete) | Small ordering nudge (A7). Visible score unchanged. |
| Yes | Yes, but one set is stale or damaged | None (treated as not taken). |
| Different quiz versions | — | None. |

## A12. Q9 / hard-axis behaviour

Question 9 asks where the member stands on having children (want soon and co-parent / want soon, traditional roles / open either way / don't want, or decide much later). It is the only question that can act as a dealbreaker.

- The pairings *want soon* + *don't want / decide later* score 0 for that question and mark a **hard-axis conflict**.
- That caps the pair's Psychology score at 40 and demotes the pair's Discover ordering by 10 points.
- It is a **demotion, never removal**: the two members still see each other, just further down.
- "Open either way" paired with either side produces only a soft, private discussion note; it does **not** demote and does **not** escalate anything else (a fix made during this work — previously it wrongly escalated a timeline note).
- The dealbreaker only applies if **both** members answered every question, so it can never be triggered by a missing or partial answer.

## A13. What members can and cannot see

**A member can see:** their own saved answers (labels and dates) and their own "completed" status.

**A member cannot see, anywhere:** another member's answers; whether another member took the quiz; any Psychology score or percentage; any compatibility breakdown; any discussion note or dealbreaker flag; any hint that a candidate's position in their feed was influenced by Psychology.

The Discover fields `psychologyMatchPercent` (always `0`) and `isPsychologyCompleted` (always `false`) are **deliberately not populated** — exposing either would let one member work out another's answers by re-answering and watching the number move.

## A14. Privacy and security protections

- **No score leaks.** Visible scores don't depend on quiz data at all.
- **Retake cooldown** (A5) slows anyone probing by re-answering.
- **The "next page" pointer is sealed** (AES-256-GCM authenticated encryption) and tied to the member it was issued to. Previously it was readable and forgeable: it carried the internal ordering number, so a member could have read it or crafted one to binary-search a candidate's exact value. Old, tampered or someone else's pointers are simply ignored (the feed starts from page 1).
- **Answers never reach logs or error messages.** Database error text can include the data being written, so it is never logged or returned; only the kind and code of the error are recorded.
- **Only your own answers are ever returned** by any endpoint. The backend has no route to read anyone else's, and the module that could have produced discussion notes was removed as dead code.
- **Bounded input:** at most 50 answers; text fields have length caps.
- **Rate limiting:** the submit endpoint uses the stricter "write" rate-limit tier (20/minute per IP), in addition to the cooldown.
- **Ownership** always comes from the verified sign-in token, never from anything the client sends.

## A15. Discover fail-open behaviour

**Rule:** Psychology may never turn `GET /discover` into an error, and may never cost a member their score.

- Psychology's data lookups run under a **time budget** (default 800 ms). A slow or hung lookup is abandoned; Discover moves on.
- A **circuit breaker** pauses Psychology lookups for 30 seconds after 3 failures in a row, so a struggling database isn't hammered.
- A **kill switch** (`PSYCHOLOGY_MATCHING_ENABLED=false`) turns Psychology off with no queries at all; the feed is then identical to before Psychology existed.
- The **quiz definition is cached** for a minute (15 seconds when absent); if a refresh fails, the previous copy keeps being used for up to 10 minutes.
- The **member's own lookup runs at the same time as** the candidate lookup, so for members who haven't taken the quiz Psychology adds essentially no waiting.
- **Bad data is tolerated everywhere**: damaged saved answers, malformed rules, missing quiz, incomplete or out-of-date answers, or an unexpected error while scoring one pair — each simply means *no Psychology for that member or pair*.
- **One bad pair never affects the others.**
- Failures are logged (at most once a minute per kind, with no member data) and counted.

**Proof.** With the real feed, scoring and ordering code running and only the database faked, ten different faults were injected — quiz lookup failing or hanging, the member's own lookup failing/hanging/returning damaged data, the candidate lookup failing/hanging, no quiz, the kill switch off, all candidates' data damaged. **In every case the feed returned normally, with the same order and the same scores as the Psychology-off feed.** Deliberately breaking the guard made 5 of those tests fail, confirming they genuinely protect the behaviour.

## A16. Database and data-integrity protections

A new migration, `20260925120000_psychology_integrity_hardening`, is **additive only** — it updates and deletes no existing rows:

- Each quiz has **at most one question per position and per topic** (unique constraints).
- **At most one active quiz** at a time (unique constraint), plus a deterministic "newest wins" tiebreak in code.
- Each saved response records **which quiz version it was given against** (existing rows left blank, which counts as current, so nobody's existing answers are invalidated).
- **Deleting a quiz that has saved answers is refused** (previously it would silently delete every member's answers). Deleting a *member* still removes their answers.
- **Shape checks** on stored data: answers must be an object; options and rules must be lists. (Applied to new and changed rows only, so old rows can never block the migration.)
- **Seeding:** `pnpm seed:quiz` seeds only the quiz; re-running never re-activates a retired quiz and warns if two are active.
- **Content is pinned by a test** so released questions can't be edited in place.

**Verified on a real Postgres engine** (an in-process build, never the shared database): all 27 migrations replay from empty; the "no schema drift" check used by CI reports no difference; and a 29-check integration run passed 29/29, including 8 simultaneous first submissions (exactly one saved row, no errors) and 6 simultaneous retakes (one rewrite).

Pre-deploy note: the migration fails cleanly (changing nothing) if a hand-edited database already has two active quizzes or duplicate question positions. The queries to check are at the top of the migration file.

---

## A17. Every issue from the original audit — and its resolution

| # | Audit issue | Resolution |
|---|---|---|
| C-1 | A Psychology failure returned a 500 from Discover | Fail-open everywhere: time budget, circuit breaker, kill switch, per-pair isolation, validated data. Ten-fault injection test. |
| C-2 | Extra sequential database calls on every Discover request | Quiz cached in memory; member lookup overlaps the candidate query; narrower data selected. |
| C-3 | Submitting the quiz didn't tell the feed to refresh | Emits the existing feed-refresh event (new reason `psychology_updated`) after a real change. |
| C-4 | Weights totalled 115 | Psychology removed from the model; total is 100 again (A8). |
| C-5 | Two simultaneous first submissions could error | Create-then-conditional-update, settled by the database's unique key; verified with 8-way concurrency. |
| C-6 | "One active quiz" was only a convention | Unique constraint + deterministic ordering; seeder no longer re-activates a retired quiz. |
| C-7 | Discover cards say 0% / "isPsychologyCompleted: false" | Intentionally kept: exposing a Psychology number is now the leak being prevented (A13). Comment corrected. |
| B-1 | Damaged data or rules could crash scoring | Scoring cannot throw on stored data; invalid data reads as "unanswered". |
| B-2 | Mixed-population ranking bias; hard axis barely mattered | Replaced by the capped ordering adjustment; hard axis is a clear −10 (A7, A12). |
| B-3 | Quiz content / version could drift silently | Version stamp on responses; stale answers ignored; content pinned by a test. |
| B-4 | Pairs scored on only some questions | A pair not scored on every question gets no Psychology effect. |
| B-5 | Quiz only seedable via the full seed (which also creates the admin) | `pnpm seed:quiz`. |
| B-6 | Exact scores and unlimited retakes could leak answers | Visible scores independent of quiz; 7-day retake wait; sealed feed pointer. |
| B-7 | No time limit on Psychology lookups | 800 ms budget + circuit breaker. |
| B-8 | Hard-coded dimension names; unused question type | Hard axis now driven by the question's stored type; remaining name-dependent rules guarded by a test. |
| B-9 | Migration/schema hygiene, schema drift | New additive hardening migration; drift fix (PR #89 hunk) included. |
| B-10 | Q10 escalation over-triggered; could lower severity | Only a medium-or-higher Q9 conflict escalates; severity can only rise. |
| B-11 | Feed position could shift if scores change mid-scroll | Refresh event on submit + sealed pointer. Remaining inherited limitation noted in A18. |
| B-12 | Assorted low items | Dead service removed; retake refreshes `completedAt`; damaged answers handled; input bounds; stale comments corrected; safe logging. |

## A17b. Additional issues discovered during implementation

| Issue | Resolution |
|---|---|
| The feed "next page" pointer could be forged to binary-search a candidate's exact ordering value, and could be read to leak it | Sealed and viewer-bound. |
| Database error messages (which embed the data written) could reach logs and responses | Only error class and code are logged; the save path returns a generic message. |
| A retake cooldown would have wrongly blocked members whose answers a quiz update made stale | Stale, damaged and other-version responses bypass the wait. |
| A cooldown checked before writing could be beaten by simultaneous requests | The check is part of the database update itself. |
| Two of my own test fixtures contained a real Q9 conflict, and one test was clock-dependent | Fixed; the clock is frozen in that test. |
| The earlier schema-drift failure had already broken CI upstream (PR #89) | Same fix included; verified with the CI drift check. |

## A18. Remaining known limitations

1. **Ordering can still be studied.** Even with hidden scores, a sealed pointer and a 7-day wait, someone who creates many fake accounts could still, slowly, infer answers from how ordering shifts. This is mitigated, not impossible.
2. **The waiting period is not visible to the app.** No field says "you can retake on X". The app only learns by being blocked (HTTP 429) or by estimating (Part B, F-2).
3. **The profile-completion card is not version-aware.** The backend marks the Psychology card "complete" if the member has *any* saved response for *any* quiz, so a member whose answers went stale may see "completed" there while the quiz screen says "not taken". It has no effect on scores. *(Found while reviewing the Flutter code; not changed, because this work was limited to the fixes already delivered.)*
4. **Hard-axis demotion is a policy choice** (−10), as are the bonus (+6), the neutral point (60) and the 7-day wait. They are not yet validated against real usage and are easy to retune.
5. **Cursor stability while someone else's data changes** mid-scroll is a pre-existing property of every ranking input and is unchanged.
6. **The full application was not booted** during verification (it would have read local settings that may point at shared services). A compile-level check of the real Psychology module wiring stands in for it.
7. **The migration has not been applied to any shared database.**
8. **Cooldown message text is English only** on the server; the app should localize its own text using `retryAfterSeconds`.
9. **Repo-wide lint has ~700 pre-existing errors** (nearly all formatting); files created for Psychology are clean and edited files are no worse than before.

## A19. Verification and testing results

| Check | Result |
|---|---|
| Full backend test suite | **109 suites passed, 1,496 tests passed**, 12 snapshots passed (5 suites / 27 tests were already skipped before this work) |
| TypeScript compile | Clean |
| Production build (api, worker, scheduler, websocket) | All four compiled |
| Golden regression file vs. pre-Psychology commit | **Identical**; passes unchanged |
| Psychology-specific specs | Fail-open, refinement/ordering properties, calculator hardening, content integrity, quiz provider, repository, service (cooldown / idempotency / races / safe errors), cursor sealing, config, seeder, module wiring |
| Discover fail-open (fault injection) | 10 faults, all return the normal feed identically; mutation check confirms the tests bite |
| Migration replay on a real Postgres engine | All 27 migrations apply from empty |
| Schema-drift check (as CI runs it) | No difference detected |
| Real-database integration script | **29 / 29 passed** (constraints, seeder, cooldown, stale retake, concurrent submits/retakes, restrict/cascade, real Discover context) |
| Lint | Files created: clean. Files edited: no worse than before |

## A20. Current production-readiness assessment

- **Backend Psychology:** production-ready **once merged and deployed**, with the kill switch available. No known open backend Psychology bug or security/data-integrity issue.
- **Discover resilience:** proven against injected failures.
- **Existing matching:** proven unchanged where Psychology doesn't apply.
- **End-to-end feature:** **not yet complete for members** — the Flutter items in Part B (especially F-1, F-2 and F-3) must be done first.

**Deployment checklist (backend):** merge; run the migration's pre-deploy queries if the database was hand-edited; deploy; run `pnpm seed:quiz` in each environment; keep `PSYCHOLOGY_MATCHING_ENABLED` available as the kill switch.

---

# PART B — FLUTTER PSYCHOLOGY HANDOFF

**Scope:** every Psychology-related frontend issue verified in the Flutter code on `origin/main` (`2d00b0d`). No Flutter code was changed. Each finding was confirmed by reading the code; anything that is only an observation is labelled as such.

## B0. The critical rule

> **Flutter must never treat Psychology as mandatory for Discover or matching.** A member who has not taken it — or for whom Psychology is unavailable — must get the normal Discover experience, must not be shown as a worse match, and must not be hidden.

**Verdict on the current code:** Discover, the match badges, profile cards and registration do **not** depend on Psychology and do not penalise anyone — with **one exception (F-3)**, a search filter that hides members who have not taken it (and, because of a backend/Flutter mismatch, hides everyone).

## B1. What Flutter currently does (verified)

| Area | Current behaviour |
|---|---|
| Endpoints used | `GET /psychology/quiz/active`, `GET /psychology/quiz/me`, `POST /psychology/quiz/submit` — `ApiPersonalityRepository` is the default repository |
| Where Psychology is called | Only the quiz page, the profile page's status section, the profile-review page, and one registration helper. **Discover, search, matches, chat never call it.** |
| Quiz page | Phases: checking → intro → one question per screen → completed. Progress bar and "Question X of N" use the server's question count (not hardcoded to 10). |
| Answering | Option **key** stored per question id; Next disabled until an option is chosen; Back keeps answers. |
| Submit | Blocks double-tap; refuses if any question is unanswered and jumps to the first gap; sends quiz id + answers in question order. |
| Errors | 404 → "No quiz available"; 400 → reloads the quiz, keeps still-valid answers, shows "quiz has been updated"; anything else → "Could not submit… check your connection". |
| After submit | Shows the saved answers and "Updated {date}"; invalidates the profile-status provider. |
| Existing state | On open, calls `GET /me`; a saved response opens the completed state; **any error falls through to the intro**. |
| Discover cards | Render `aiMatchPercent` (labelled "AI Match") and overall; zero values are hidden. `psychologyMatchPercent` / `isPsychologyCompleted` are parsed but never rendered. |
| Feed refresh | A realtime `feed.invalidate` event invalidates the Discover, reel and search providers. |
| Registration | The quiz is **not** part of the required wizard flow; it is an optional card / review-page section. |
| Tests | Solid coverage of loading, answering, submit, 400/404/network failures, retake prefill, models. **No test for 429.** |

## B2. Issues, in priority order

### F-1 — HIGH — The 7-day retake wait (HTTP 429) is not handled, and shows the wrong message

- **Current behaviour:** `PersonalityQuizNotifier.submit()` catches `ApiException` and maps every status except 400 and 404 to `QuizError.submitFailed`, whose text is *"Could not submit your answers. Check your connection and try again."* (`personality_provider.dart`, `submit()`; `psychologySubmitError`). Also, `unwrapOrThrow` (`core/network/api_exception.dart`) keeps only `message` and `code` — it **drops `retryAfterSeconds`** from the response body.
- **What is wrong:** a member blocked by the cooldown is told to check their connection, and "retrying" can never succeed. The app also cannot tell the cooldown 429 apart from the general per-IP rate-limit 429 (both are 429).
- **Expected behaviour:** a clear, localized message such as "You can change your answers again in N days", with no retry button; answers kept on screen or the user returned to the completed state.
- **What to change:**
  1. Carry the response body's `retryAfterSeconds` through the exception (an optional field on `ApiException`, or parsed in `ApiPersonalityRepository`).
  2. Add a `QuizError.retakeCooldown` kind carrying the remaining time; branch on **429 + `retryAfterSeconds` present** as the cooldown. A 429 *without* it is the generic rate limit ("Too many requests, wait and try again" — `apiError429` already exists).
  3. Localize the text yourself (English **and Tamil**) from `retryAfterSeconds`; do not display the server's English `message`.
  4. Hide the Retry affordance for this error.
- **Backend contract:** `429 { statusCode, error, message, retryAfterSeconds }`.
- **States:** the submit button leaves its loading state; the member's typed answers are not lost; no automatic retry.
- **Edge cases:** `retryAfterSeconds` may be very large (up to ~1 year if configured) — format as days; it may be small — never show "0 days" (round up); the server may have the cooldown disabled (`0`), in which case this never occurs.

### F-2 — HIGH — Retake is offered without any awareness of the wait, so members can answer all 10 questions and then be blocked

- **Current behaviour:** the completed screen's *Retake Quiz* button is always enabled and starts the full 10-question flow with answers pre-filled (`_ResultView`, `retake()` → `startQuiz()`).
- **What is wrong:** with the new wait, a member who changed their mind three days after submitting will answer up to ten questions and only then learn (via F-1) that they cannot save. The contract provides **no "can retake at" field**.
- **Expected behaviour:** the member is told up front when they can change their answers, before investing effort.
- **What to change (client-only, no backend change needed):** compute a **hint** from `PsychologyQuizResponse.completedAt` + the default 7 days. If the hint says "not yet", disable *Retake* and show "You can retake from {date}". **Treat the server as authoritative**: the real length is configurable, so the hint can be wrong in either direction — if the server later returns 429, use F-1; if the hint blocks but the server would have allowed, the member can be given a "try anyway" path or the hint window can be shortened. *Optional follow-up for the backend team (not required):* a `canRetakeAt` field on `GET /me` would remove the guesswork.
- **Important detail:** the server counts the wait from **`completedAt`**, not `updatedAt`. The current model exposes `lastUpdatedAt = updatedAt ?? completedAt`. For responses saved *before* the backend change, `updatedAt` can be later than `completedAt`, so a hint based on `lastUpdatedAt` may be wrong. **Use `completedAt`** for the hint.
- **Edge cases:** an **unchanged** resubmission succeeds and does not start a wait, so "Retake, keep the same answers, Submit" is harmless. A **stale** response never appears here (the server returns 404 → intro, no wait).

### F-3 — HIGH — The search filter "Completed Profile" hides every member, and violates the never-penalise rule

- **Current behaviour:** the search filter sheet has a toggle labelled **"Completed Profile"** (`searchFilterCompletedProfile`). Turning it on sets `SearchFilters.completedProfile`, and `SearchFilters.matches` (`search_filters_entity.dart`, line ~284) then does `if (completedProfile && !profile.isPsychologyCompleted) return false;`. It is applied client-side to search results (`search_providers.dart`, `filteredSearchResultsProvider`).
- **What is wrong:** (a) the label says "profile", but the code tests **Psychology completion**; (b) the backend **always** sends `isPsychologyCompleted: false` (deliberately — privacy), so with the toggle on, **every** result is removed; (c) even if the backend populated it, this would hide members solely because they had not taken Psychology — exactly what the product rule forbids.
- **Expected behaviour:** the toggle means what it says (a fully completed profile), or it is removed.
- **What to change:** test `profile.profileComplete` instead (the backend already sends it: true when the profile is 100% complete, and the entity already parses it), or remove the toggle. **Do not** filter on `isPsychologyCompleted` anywhere.
- **Backend contract:** `profileComplete: bool` on every feed/search item.
- **Edge case:** Psychology is not part of the completion percentage, so a member can be `profileComplete: true` without ever taking the quiz.

### F-4 — MEDIUM — Outdated assumptions about retakes and timestamps in code comments, models and tests

- **Current behaviour:** `PersonalityRepository.submitAnswers` says "submitting again is a retake (the backend upserts)"; `PsychologyQuizResponse` says "a retake overwrites the answers in place… the backend leaves `completedAt` at the first submission, so 'last taken' UI reads `lastUpdatedAt`"; `psychology_models_test` asserts "'last taken' reads updatedAt, not completedAt".
- **What is wrong:** the backend now refreshes `completedAt` on every real change (and the cooldown counts from it), and a retake is cooldown-limited and idempotent for identical answers.
- **What to change:** update the documentation and tests to the current semantics; decide deliberately which timestamp drives "Updated {date}" (see F-2 for the cooldown hint, which must use `completedAt`).

### F-5 — MEDIUM — Any failure checking existing answers silently shows the intro to a member who already completed the quiz

- **Current behaviour:** `_checkExisting()` swallows every error from `GET /me` and falls through to the intro (`personality_provider.dart`).
- **What is wrong:** 404 correctly means "not taken / answers no longer apply". But a network blip, 401 or 500 is indistinguishable from it, so a member who *has* answers sees "Start Quiz". Combined with the new wait, they may then answer everything and be blocked (F-1).
- **Expected behaviour:** distinguish "not taken" (404) from "couldn't check". On a failed check, offer a retry (or proceed to the intro with a light "we couldn't check your saved answers" note).
- **Edge cases:** a slow connection; sign-in expiry (the interceptor already retries once on 401).

### F-6 — MEDIUM — Feed refresh after a submit depends entirely on the realtime connection

- **Current behaviour:** after a successful submit the notifier invalidates only `myPersonalityResultProvider`. The backend emits `feed.invalidate` with reason `psychology_updated`; the app's handler (`realtime_providers.dart`) is reason-agnostic and invalidates the Discover, reel and search providers, so it **works when the socket is connected**.
- **What is wrong:** realtime delivery is best-effort. If the socket is down, the member's Discover keeps its old order until a manual refresh. The handler's explanatory comment also still lists only profile / preference / block writes.
- **What to change:** as a belt-and-braces measure, also invalidate `discoverFeedProvider`, `reelFeedProvider` and `searchResultsProvider` after a **successful** submit (harmless duplicates — the handler is idempotent). Do not treat the reason string as meaningful. Update the comment.
- **Edge case:** an unchanged resubmission emits no event; invalidating anyway just refetches once.

### F-7 — LOW/MEDIUM — Outdated or misleading copy (English and Tamil)

Verified strings and comments to review:
- `psychologyQuizTitle`: **"Psychological Quiz"** — the product is the *Marriage Compatibility Quiz* (the in-card title already uses that).
- `registrationWizardQuizHook`: **"A short personality assessment…"** and `completionCardBodyPsychology`: **"Discover your personality profile."** — the quiz produces no personality profile or score (the code's own comments say so).
- `lib/core/theme/app_colors.dart` comment: **"magenta keys psychology (OCEAN)"** — the OCEAN/20-question quiz is retired.
- **Unused strings** `homePsychologyCompletedLabel` ("Psychology Completed") and `homePsychologyMatchScoreLabel` ("Psychology Match") — no code uses them; they imply a per-member Psychology display that must **not** be built. Remove them.
- `psychologyIntroBody`: does not tell the member it is **optional**, that their answers are **private** (never shown to other members), or that **changes are limited** to once per waiting period. Recommended additions.
- Not a defect: `astroPersonalityMatch` ("Personality Match") belongs to the horoscope feature.

### F-8 — LOW — `isPsychologyCompleted` / `psychologyMatchPercent` are reserved, always-empty fields

- **Current behaviour:** both are parsed in `DiscoveryProfileModel` and carried on the entities. The backend sends `false` / `0` **by design**.
- **What to do:** never render them, never branch on them (F-3 is the one place that does). Keep tolerant parsing so a missing field doesn't crash. Add a code comment saying they are intentionally unpopulated for privacy.
- **Do not** build a Psychology badge, "psychology match %" or "took the quiz" indicator on other members' cards or profiles.

### F-9 — LOW — Profile and review surfaces: minor state handling

- **Profile page:** loading shows a spinner; **error hides the section** (good — the rest of the page continues); a member who has *not* taken it sees **nothing** in that section (no call to action; access is via the drawer item and the completion card). Consider a soft "Take the quiz" prompt.
- **Profile review page:** on a failed check, `personalityAsync.value` is null, so the section shows the "take the quiz" prompt even when the real reason is an error. Minor.

### F-10 — INFORMATION — leaving the quiz mid-way discards answers

The provider is `autoDispose` and there is no draft saving, so backing out loses answers. Acceptable for ~3 minutes; a draft is optional.

### F-11 — INFORMATION — the profile-completion card can disagree with the quiz screen

The Flutter card (`CompletionCardKeys.psychology`, `affectsScore: false`) trusts the backend's `psychology` completion flag, which counts *any* saved response (backend limitation A18-3). A member with stale answers may see the card as done while the quiz screen shows the intro. On Psychology-specific screens keep using `GET /me` as the source of truth.

## B3. Things verified as correct (do not regress)

- Quiz length, progress and options are **server-driven**; the quiz id is echoed back, never hardcoded.
- Stale-safe prefill (`_validAnswers`) drops answers whose option no longer exists.
- 400 handling reloads the quiz and points at the first gap; incomplete-submit guard; double-submit guard; failed submit keeps answers.
- **Unavailable quiz (404)** is a contained state ("No quiz available"); it doesn't affect anything else.
- Discover/search/matches/chat **never call** Psychology endpoints — a Psychology outage cannot break them.
- **Reel paging** de-duplicates by profile id, so a feed pointer the server can't open (it now restarts from page 1) can never show a profile twice. No change needed.
- Registration does **not** require the quiz; the completion card has `affectsScore: false`.
- Discover cards show only the AI-match percentage and hide zero values.
- **No OCEAN / 20-question / traits UI remains** in the code (only the comment and copy noted in F-7); the old mock repository is gone.

## B4. What Flutter must do when Psychology is unavailable

| Condition | Required behaviour |
|---|---|
| `GET /active` → 404 | Quiz page shows "No quiz is available right now." Nothing else changes. |
| `GET /active` / `/me` network or 5xx | Quiz page shows a retry state. **No other screen is affected.** |
| `GET /me` fails on the profile page | Hide the Psychology section (already the case). |
| `POST /submit` → 500/network | Keep answers, show a generic retry message (already the case). |
| `POST /submit` → 429 with `retryAfterSeconds` | Cooldown message (F-1). |
| `POST /submit` → 429 without it | Generic rate-limit message. |
| Discover for a member without Psychology | **Exactly the normal experience.** Never show a lower or missing score. |
| Anything on another member | Never show Psychology information. |

The rest of the app must continue normally in every case above.

## B5. Loading, empty, retry and error states to support

| Screen | Loading | Empty | Error | Retry |
|---|---|---|---|---|
| Quiz — checking existing | spinner | — | F-5: distinguish 404 from failure | Yes (on failure) |
| Quiz — loading questions | spinner | "No quiz available" (404) | load-failed message | Yes |
| Quiz — submitting | button loading | — | 400: "quiz updated"; **429: cooldown (F-1)**; other: generic | Yes, **except** cooldown |
| Completed screen | — | — | — | Retake (aware of the wait, F-2) |
| Profile Psychology section | spinner | hidden or soft prompt (F-9) | hidden | — |
| Discover / search | unchanged | unchanged | unchanged | unchanged |

---

# FLUTTER IMPLEMENTATION CHECKLIST

Everything below must be complete before Psychology is fully integrated end-to-end. **No item requires a backend change.**

**Must do (blocks a correct end-to-end experience)**
- [ ] **F-1** Carry `retryAfterSeconds` from the 429 body into the app's exception/repository layer.
- [ ] **F-1** Add a retake-cooldown error kind; show a localized (EN + TA) "you can change your answers again in N days" message; never show "check your connection" for it; no Retry button.
- [ ] **F-1** Keep generic per-IP 429 (no `retryAfterSeconds`) as a separate "too many requests" message.
- [ ] **F-2** Make *Retake* aware of the wait: use `completedAt` + 7 days as a hint, disable/annotate the button with the date, and still handle a server 429 as the authority.
- [ ] **F-3** Fix or remove the search "Completed Profile" filter: use `profileComplete`, never `isPsychologyCompleted`.
- [ ] **F-5** Distinguish "not taken" (404) from "could not check" when opening the quiz; offer retry on a failed check.

**Should do**
- [ ] **F-6** After a successful submit, also invalidate `discoverFeedProvider`, `reelFeedProvider` and `searchResultsProvider`; update the realtime comment.
- [ ] **F-4** Update repository/model doc comments and the "updatedAt vs completedAt" test to the current semantics.
- [ ] **F-7** Fix the outdated copy (English and Tamil): quiz title, wizard hook, completion-card body, the OCEAN comment; remove the unused `homePsychology*` strings.
- [ ] **F-7** Add to the intro: optional, private (never shown to others), and changes are limited to once per waiting period.
- [ ] **F-8** Add a comment that `isPsychologyCompleted` / `psychologyMatchPercent` are intentionally unpopulated; add a lint-style test that no widget renders them.

**Nice to have**
- [ ] **F-9** Soft "Take the quiz" prompt on the profile page for members who haven't taken it; don't show "take the quiz" on the review page when the check merely failed.
- [ ] **F-10** Optional local draft so leaving the quiz doesn't lose answers.

**Tests to add**
- [ ] 429 with `retryAfterSeconds` → cooldown message, no retry, answers kept.
- [ ] 429 without it → generic rate-limit message.
- [ ] `GET /me` failure (non-404) → retry state, not silently the intro.
- [ ] Retake button disabled with a date inside the hint window; enabled after it; server 429 overrides an "enabled" hint.
- [ ] Search "Completed Profile" filter keeps members who haven't taken Psychology.
- [ ] Successful submit invalidates the Discover/reel/search providers.
- [ ] Quiz 404/5xx never affects Discover, profile or search screens.
- [ ] A member without Psychology renders the normal card, match percentage and profile.

**Guardrails (must remain true)**
- [ ] Psychology is never required for registration, Discover, matching or chat.
- [ ] No UI shows another member's Psychology status, score, badge, answers or notes.
- [ ] A member is never displayed as a worse match because Psychology is incomplete or unavailable.

---

# BACKEND ↔ FLUTTER CONTRACT SUMMARY

All three endpoints require a signed-in member (Firebase bearer token). All belong to the signed-in member only.

### `GET /psychology/quiz/active`
- **Receives (200):** `{ id, title, description, version, questions: [ { id, order, dimension, questionText, options: [ { key, label, value } ] } ] }` — never any scoring rules.
- **Errors:** `404` no active quiz.
- **Flutter:** sort by `order`; render options by `key`/`label`; ignore `value`.

### `GET /psychology/quiz/me`
- **Receives (200):** `{ quizId, answers: [ { questionId, dimension, questionText, selectedKey, selectedLabel } ], completedAt, updatedAt }`.
- **`404` means:** not taken **or** saved answers no longer apply (question added, option changed, quiz version moved on, or damaged data). Treat as "show the quiz". **No waiting period applies to a stale retake.**

### `POST /psychology/quiz/submit`
- **Sends:** `{ quizId, answers: [ { questionId, selectedKey } ] }` — exactly one answer per question; `answers` 1–50 items; `questionId` ≤ 100 chars; `selectedKey` ≤ 20; `quizId` non-empty ≤ 100.
- **Receives (200):** the same shape as `GET /me`.
- **Behaviour:** first submission → saved. Same answers again → `200`, unchanged. Different answers after the waiting period → saved (waiting period restarts). Stale saved answers → saved immediately.

| Status | Meaning | Flutter should |
|---|---|---|
| `200` | Saved / unchanged | Show completed state; refresh feeds |
| `400` | Wrong quiz id, missing/duplicate/unknown/invalid answers, or bounds exceeded | Reload the quiz, keep valid answers, "quiz has been updated" |
| `401` | Signed out | Existing auth handling |
| `404` | No active quiz | "No quiz available" |
| **`429` + `retryAfterSeconds`** | **Retake wait active** (default 7 days) | Localized cooldown message; no retry |
| `429` (no `retryAfterSeconds`) | General per-IP rate limit | "Too many requests, wait and try again" |
| `500` | Save failed (generic message, no member data) | Generic retry; keep answers |

Cooldown body: `{ "statusCode": 429, "error": "Too Many Requests", "message": "You can change your quiz answers again in N days.", "retryAfterSeconds": <int> }` — `message` is English only; localize from `retryAfterSeconds`.

### Discover / search / matches (existing endpoints)
- **Receives:** the same fields as before. `compatibility.aiMatchPercent`, `overallCompatibility` and the band are **identical with or without Psychology**.
- **`compatibility.psychologyMatchPercent` = `0` and `isPsychologyCompleted` = `false` for every member, by design.** Never render or filter on them.
- **`profileComplete`** (bool) is the correct "completed profile" flag.
- **`nextCursor`** is now a sealed, opaque string tied to the member. Send it back unchanged. If the server can't open it (old, altered, or another member's), it silently returns the first page — dedupe by profile id (the reel already does).

### Realtime
- **`feed.invalidate`** is emitted after a submit that actually changed answers, with `reason: "psychology_updated"`. The client should refetch feeds and should not depend on the reason. Delivery is best-effort — also invalidate locally after a successful submit (F-6).

### Effect on ordering (for understanding only; nothing is sent)
Psychology can nudge order by up to +6, or −10 for a stated hard-axis conflict, only when both members have valid answers. It never changes a visible number and never hides anyone.
