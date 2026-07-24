# Edit-Mode "Continue" Performance Investigation

Status: **2 optimizations shipped and verified on a real device. Further options diagnosed but NOT implemented — pending approval.**

This doc is the full handoff for the investigation into why the registration
wizard's edit-mode "Continue" button (Edit Profile → change a field → Continue
→ back to Discover) was slow, what was changed, what was measured, and what
remains on the table.

---

## 1. Background

**Symptom:** tapping "Continue" from an edit-mode wizard screen (opened via
drawer → Edit Profile / Verification Center) took several seconds before
landing back on Discover.

**Root cause (established before this doc, still valid):** the backend talks
to a **Neon Postgres instance in `us-east-1`**, and this dev/test environment
is geographically far from it. Every single DB round trip costs **~250–300ms**
network RTT, confirmed directly (raw TCP connect, cold connect+auth, warm
`SELECT 1` — see [§5](#5-db-latencyregion-diagnostics)). This is a fixed cost
per round trip, not a symptom of a slow query, a bad index, or pool
contention — **no single SQL query and no pool-contention was ever found to
be the cause.**

Given that floor, total latency is a direct function of **how many
sequential DB round trips** the edit-mode Continue path requires. Two
already-shipped-before-this-doc fixes established that framing:

- `skipMaterialize=true` — edit-mode PATCH calls skip `syncMatchableFromDraft`
  (the CREATE-mode auto-materialize step) because `finalize()` is called
  unconditionally right after anyway and would just redo the same work.
- The 3 writes inside `writeProfileFromDraft` (`user_profiles`,
  `astrology_profiles`, `partner_preferences`) and the 4 reads inside
  `getOwn()` were already parallelized via `Promise.all` before this round of
  work — see `apps/api/src/modules/profiles/services/profile.service.ts`.

This doc covers the round of work **on top of that**: 2 more read
eliminations (implemented), a full round-trip audit of the entire path
(diagnostic only), and 3 graduated proposals for closing the remaining gap to
a **<1s** target (none implemented — awaiting approval).

**Temporary instrumentation:** the codebase currently has `[STORY-PERF-SRV]` /
`[STORY-PERF-SQL]` / `[STORY-PERF-POOL]` `console.log`s in
`profile.service.ts`, `profile-draft.controller.ts`, `profile.controller.ts`,
`firebase-auth.guard.ts`, `prisma.service.ts`, `main.ts`, plus a
`[STORY-PERF]` Dart equivalent in `Frontend/lib/core/utils/story_perf.dart`
(and its call sites in `profile_wizard_page.dart`,
`registration_repository.dart`, `api_interceptor.dart`). These are explicitly
marked `TEMP` in their own comments and exist **only** to make this kind of
diagnosis possible without extra tooling. **Someone should remove them once
this investigation is closed out** — they're not meant to ship long-term.

---

## 2. What was actually changed in this round (implemented, tested, verified)

Both changes are in `backend/apps/api/src/modules/profiles/services/profile.service.ts`.
Both are pure "reuse data we already have" changes — **no new SQL, no new
endpoints, no schema change, no API contract change, no behavior change.**

### 2.1 Reuse `upsertProfile()`'s returned row instead of re-`SELECT`ing `user_profiles`

**Before:** `writeProfileFromDraft()` wrote `user_profiles` and discarded the
returned row. `recalculateAndPersistCompletion()` → `getOwn()` then did a
fresh `SELECT * FROM user_profiles WHERE user_id=$1` a few hundred
milliseconds later to get a row that was — byte for byte — the same data
just written (nothing else touches `user_profiles` in between).

**After:** `writeProfileFromDraft()` now returns the `ProfileEntity` from its
own `upsertProfile()` call. `getOwn()` takes two new optional parameters,
`prefetchedProfile` and `prefetchedPhotos`; when supplied, it uses them
instead of re-querying:

```ts
async getOwn(
  userId: string,
  prefetchedProfile?: ProfileEntity,
  prefetchedPhotos?: PhotoEntity[],
): Promise<ProfileEntity> {
  const [profile, photos, partnerPreference, astrology] = await Promise.all([
    prefetchedProfile
      ? Promise.resolve(prefetchedProfile)
      : this.profileRepository.findProfileByUserId(userId),
    prefetchedPhotos
      ? Promise.resolve(prefetchedPhotos)
      : this.photoRepository.findAllForUser(userId),
    this.profileRepository.findPartnerPreference(userId),
    this.profileRepository.findAstrologyProfile(userId),
  ]);
  ...
```

`recalculateAndPersistCompletion()` gained the same two optional params and
just forwards them into `getOwn()`. `finalize()` and `syncMatchableFromDraft()`
now capture `writeProfileFromDraft()`'s return value and pass it through.
`GET /profiles/me` (the only caller that calls `getOwn()` with **no**
prefetched data) is completely unaffected — same query, same result.

**Saves:** 1 DB round trip, every single `finalize()` call, unconditionally.

### 2.2 Fetch `profile_photos` once instead of `COUNT` then re-fetch

**Before:** `finalize()` called `photoRepository.countForUser(userId)`
(`SELECT COUNT(*) FROM profile_photos ...`) purely to gate "at least one
photo required." Moments later, `recalculateAndPersistCompletion()` →
`getOwn()` called `photoRepository.findAllForUser(userId)`
(`SELECT * FROM profile_photos ... ORDER BY order`) for the *same user's
same photos* — two separate queries against the same table for the same
call.

**After:** `finalize()` now calls `findAllForUser()` **once**, uses
`photos.length === 0` for the gate (identical semantics — a `COUNT` and an
array length check the same condition), and passes that `photos` array
through to `recalculateAndPersistCompletion(userId, writtenProfile, photos)`,
which forwards it into `getOwn()` as `prefetchedPhotos`.

**Saves:** 1 DB round trip, every single `finalize()` call, unconditionally.

### 2.3 Net effect on `finalize()`'s round-trip count

| | Before this round | After this round |
|---|---|---|
| `user_profiles` touches | 1 write + 1 read (redundant) | 1 write only |
| `profile_photos` touches | 1 `COUNT` + 1 `SELECT *` (redundant) | 1 `SELECT *` only |
| **Total DB round trips saved per `finalize()` call** | — | **2**, ~560ms at the measured 255–300ms RTT |

### 2.4 What was explicitly NOT touched

- Registration architecture, DB schema, API contracts — unchanged.
- `finalize()` was not removed; `skipMaterialize=true` behavior unchanged.
- All validation/business rules unchanged (`missingRequiredFields`,
  `isPhysicalDetailsValid`, `isEducationDetailsValid`, `isLifestyleDetailsValid`,
  `isHoroscopeDetailsValid` — untouched).
- Profile completeness calculation (`calculateCompletion()`) — untouched,
  byte-for-byte same logic, just fed data from a different source (a write's
  return value instead of a subsequent read of the identical row).
- No Redis/cache/background jobs added.
- The existing `Promise.all` parallelization inside `writeProfileFromDraft`
  and `getOwn` (already in place before this round) was left as-is — not
  reverted, not extended.

---

## 3. Verification performed

### 3.1 Static checks

- `npx tsc -p tsconfig.json --noEmit` — no new type errors (1 pre-existing,
  unrelated error in `libs/config/src/config.service.spec.ts`, not touched by
  this change).
- `npx eslint` on the exact files changed
  (`profile.service.ts`, `profile.repository.ts`, `photo.repository.ts`) —
  **zero** lint errors. (The full `modules/profiles/**` glob has ~58
  pre-existing lint errors — mostly Prettier formatting — in files this
  change never touched; not introduced by this work.)

### 3.2 Unit tests

Updated `apps/api/src/modules/profiles/tests/profile.service.spec.ts` to
match the new call shape (`finalize()` now sources its photo gate from
`findAllForUser` instead of a separately-mocked `countForUser`; default mock
returns one photo so existing "finalize succeeds" tests keep passing, and the
one photo-required-rejection test now overrides `findAllForUser` to `[]`
instead of `countForUser` to `0`).

```
npx jest apps/api/src/modules/profiles
Test Suites: 6 passed, 6 total
Tests:       1 todo, 63 passed, 64 total
```

### 3.3 Three real physical-device tests (USB, not emulator)

Backend rebuilt (`npm run build:api`) and restarted fresh against the real
Neon `us-east-1` DB so the pool started cold, then warmed up naturally across
the 3 tests (exactly as it would in production). Phone connected via USB,
`adb reverse tcp:3000 tcp:3000`, `adb logcat` filtered for `[STORY-PERF]`
(frontend timestamps) cross-checked against the backend's own
`[STORY-PERF-SRV]` console timestamps for the same requests.

| | PATCH | finalize | Continue → Discover |
|---|---|---|---|
| Test 1 (physical-details, cold pool) | 1733ms | 1915ms | 4250ms |
| Test 2 (education-details, warm pool) | 1015ms | 1890ms | 3153ms |
| Test 3 (lifestyle-details, warm pool) | 915ms | 2201ms | 3301ms |

Frontend and backend timestamps matched within ~20–80ms (Firebase
token-verify + Dio overhead) on all 3 — these are real end-to-end numbers.

**Query-log verification (all 3 tests):** pulled the exact SQL sequence for
each `finalize()` call from the backend log. All three show the identical,
reduced 6-round-trip shape (`getDraft → profile_photos SELECT once →
[3 parallel writes] → markComplete → [2 parallel reads] → pct UPDATE`), with
zero `COUNT(*) FROM profile_photos` and zero extra `SELECT ... FROM
user_profiles` — confirming both eliminations are live in real traffic, not
just theoretical.

**Correctness checklist:**
- Edited values persisted: yes (no errors in backend log across all 3 tests;
  each PATCH/finalize pair completed with the app landing on Discover with
  the success snackbar, which only happens on the non-error code path).
- `profile_complete_pct` / `is_profile_complete`: logic is provably unchanged
  — same calculation, same inputs, just sourced from a write's return value
  instead of a redundant re-read of the identical row. Backed by the 24
  passing `ProfileService` unit tests including explicit completion-percentage
  assertions.
- Discover eligibility: unchanged — `isProfileComplete: true` is still set
  unconditionally in the same write.
- Photos / astrology / partner preferences: unchanged — same UPDATE/SELECT
  calls for those tables as before; only the 2 proven-redundant reads were
  removed.
- App-restart persistence: **not explicitly re-tested in this round** (no
  restart was performed between the 3 tests) — this optimization doesn't
  touch anything restart-relevant (persistence is Postgres, not app state),
  but flagging that it wasn't re-verified here for completeness.

---

## 4. Remaining latency after this round

| Stage | Warm measured |
|---|---|
| PATCH | ~0.9–1.0s |
| finalize | ~1.9–2.2s |
| **Continue → Discover total** | **~3.0–3.3s** |

Still well above the user's target of **<1 second**.

---

## 5. DB latency/region diagnostics

All measured from this dev environment against
`ep-cold-king-aud2tbq0-pooler.c-10.us-east-1.aws.neon.tech` (Neon pooled
endpoint, AWS `us-east-1`):

| Test | Result |
|---|---|
| Raw TCP connect only (10 samples) | min 248ms / median 301ms / max 1639ms |
| Cold connect + `SELECT 1`, fresh pool each time (10 samples) | min 1821ms / median 2235ms / max 3011ms |
| Warm `SELECT 1`, same open connection (10 samples) | min 247ms / median 255ms / max 994ms |

**Interpretation:** ~250–300ms is the network-RTT floor for *every* round
trip once a connection is warm — this is geographic distance, not a Postgres
or Prisma cost. TLS+auth handshake on a cold connection adds another
~1.9–2.7s on top, which is why `pg.Pool`'s `min: 1` keepalive (already in
`prisma.service.ts`) matters — see its inline comment for the original 5+s
bug that fix addressed.

**Pool contention:** ruled out as a steady-state cause. `pool.totalCount`
climbing 1→3→4 lines up exactly with the one-time cold-connect spikes at
startup; once stable at 4 connections, `waiting` stays at 0 and every query —
including previously-slow ones — runs at the same ~255–300ms baseline.

**Single slow query:** ruled out. The exact same query measured 4607ms once
(cold connection) and 289–317ms three samples later (warm) — the query
itself does nothing expensive.

**User's explicit decision:** keep the Neon `us-east-1` database. Do not
migrate/test a closer region (e.g. Singapore) for now — this was raised as an
option and declined in favor of investigating code-side round-trip
reductions first.

---

## 6. Full edit-mode Continue path — every DB operation

This is the complete map used to derive §7's three options. "Stage" = a
sequential `await` in the current code; operations in the same stage already
run concurrently via `Promise.all`.

`Flutter: Continue tapped → PATCH /profiles/draft/:section?skipMaterialize=true → POST /profiles/finalize → navigate to Discover`

| # | Request | SQL operation | Why | Required for edit mode? | Gates navigation? | Reusable? | Parallelizable? |
|---|---|---|---|---|---|---|---|
| 1 | PATCH | `SELECT users WHERE firebase_uid=$1` (auth guard) | Resolve internal user id from Firebase token | Yes | Yes | No — first touch | No — gates `userId` |
| 2 | PATCH | `INSERT registration_steps ... ON CONFLICT ... RETURNING` (`getOrCreateRegistrationStep`, called inside `mergeDraftSection`) | Read existing draft JSON to merge new section into it in JS | Yes, under current merge-in-JS design | Yes | No today — a `jsonb_set` UPDATE could remove this read entirely (not implemented) | No — op 3 needs its result |
| 3 | PATCH | `UPDATE registration_steps SET draft_data=..., completed_steps=..., current_step=... RETURNING` | Persist merged draft | Yes | Yes | N/A (write) | No — depends on op 2 |
| 4 | finalize | `SELECT users WHERE firebase_uid=$1` (auth guard again) | Same user as op 1, ~1s later, separate HTTP request | Yes (per-request guard, no cross-request memory) | Yes | **Fully redundant with op 1** at the business-transaction level — only removable by merging the 2 HTTP requests into 1 | No |
| 5 | finalize | `INSERT registration_steps ... ON CONFLICT ... RETURNING` (`getDraft`) | Re-read draft to validate + build materialize payload | Yes, under current design | Yes | **Fully redundant with op 3's own `RETURNING`** — that exact row was already in hand one HTTP response ago | No (needs `userId` from op 4) |
| 6 | finalize | `SELECT profile_photos WHERE user_id=$1 ORDER BY order` | Photo-required gate + `photos` completion-section input (already merged into 1 query as of §2.2) | Yes | Yes — must complete+pass before any write (partial-write safety) | Already optimized | Yes, with op 5 — no real dependency on the draft, only on `userId`. Currently sequential in code for no structural reason. |
| 7 | finalize | `UPDATE partner_preferences ... RETURNING` (conditional) | Materialize partner-pref section if present in draft | Only if section has data | Yes | N/A (write) | Yes — already parallel with 8/9 |
| 8 | finalize | `UPDATE astrology_profiles ... RETURNING` (conditional) | Materialize horoscope section if present | Only if section has data | Yes | N/A (write) | Yes — already parallel with 7/9 |
| 9 | finalize | `UPDATE user_profiles SET ..., profile_complete_pct=0(placeholder) RETURNING` | Materialize profile row | Yes (always) | Yes | Its `RETURNING` is reused later — see §2.1 | Yes — already parallel with 7/8 |
| 10 | finalize | `UPDATE registration_steps SET is_complete=true RETURNING` (`markComplete`) | Mark onboarding wizard complete | **Arguably not, for edit mode** — you can only reach edit mode if this is already `true`; re-setting it is an idempotent no-op | No | N/A | Yes — could fold into 7/8/9's batch, or be skipped for edit-mode calls (needs sign-off — this is a behavior-scoping decision) |
| 11 | finalize | `SELECT partner_preferences WHERE user_id=$1` | Completion-calc input + returned in API response body | Yes | Yes | Reusable only when op 7 ran this same call (narrow — none of the 3 measured tests touched this section) | Already parallel with 12 (inside `getOwn`'s `Promise.all`) |
| 12 | finalize | `SELECT astrology_profiles WHERE user_id=$1` | Same, for astrology | Yes | Yes | Same narrow reuse as 11 | Already parallel with 11 |
| 13 | finalize | `UPDATE user_profiles SET profile_complete_pct=$real` | Persist real percentage now that 11/12 are known | Yes | Yes | No — needs 11/12's result | No — must follow 11/12 |

**Current sequential stages (as shipped after §2):** 7 —
`auth → getDraft → photos → [writes×3] → markComplete → [reads×2] → pctUpdate`.
This matches the measured backend `finalize()` time (1.8–2.2s ≈ 7 × ~260–300ms).

---

## 7. Three proposed options to close the gap to <1s (DIAGNOSED ONLY — NOT IMPLEMENTED)

None of these have been implemented. All require explicit approval before
any code is written.

### Option A — Minimal

Pure reordering of *existing* queries. No new SQL, no new endpoints, no
contract change.
1. Fire `getDraft` (op 5) and `photos` (op 6) concurrently — neither depends
   on the other.
2. Fold `markComplete` (op 10) into the same `Promise.all` as ops 7/8/9.

| | Before | After |
|---|---|---|
| PATCH round trips | 3 | 3 (unchanged — op 1→2→3 are genuinely sequential) |
| finalize sequential stages | 7 | 5 |
| Estimated finalize latency | ~1.8s | ~1.3s |
| Estimated PATCH latency | ~0.95s | ~0.95s |
| **Estimated Continue → Discover** | ~3.0–3.3s | **~2.5–2.8s** |

Files: `profile.service.ts` (`finalize()` only). Risk: very low. API
contract: none. Schema: none. **Does not get near 1s.**

### Option B — Moderate

Option A, plus:
1. Rewrite `mergeDraftSection` to a single `jsonb_set` UPDATE (removes op 2
   entirely) — parameterized, no injection risk (`section` is always one of
   the 10 fixed `DRAFT_SECTIONS` values), no schema change (`draft_data` is
   already `jsonb`).
2. Let `POST /profiles/finalize` accept an optional body carrying the draft
   data the client already received from the immediately-preceding PATCH
   response (edit mode only) — skips op 5 (`getDraft`) when present. Falls
   back to today's behavior with no body (Profile Review / initial
   registration unaffected).

| | Before | After (B) |
|---|---|---|
| PATCH round trips | 3 | **2** |
| finalize sequential stages | 7 | **4** |
| Estimated finalize latency | ~1.8s | ~1.0–1.1s |
| Estimated PATCH latency | ~0.95s | ~0.65s |
| **Estimated Continue → Discover** | ~3.0–3.3s | **~1.9–2.2s** |

Files: `profile.repository.ts`, `profile.service.ts`, `profile.controller.ts`,
plus **frontend** (`registration_repository.dart`, `profile_wizard_page.dart`
must pass the PATCH response into the finalize call). Risk: moderate — new
`jsonb_set` merge semantics need test coverage; echoed draft data needs
scoping to the edit-mode path only. API contract: yes (new optional field,
backward compatible). Schema: none. **Real progress, still not <1s.**

### Option C — Maximum performance

One new edit-mode-only endpoint (e.g. `PATCH /profiles/edit/:section`) that
authenticates once, validates once, and commits once. Existing PATCH/finalize
endpoints stay untouched for CREATE-mode/initial registration.

1. Auth once (ops 1/4 collapse into 1).
2. One `jsonb_set` UPDATE on `registration_steps`, `RETURNING draft_data` —
   full merged draft in hand, so op 5 is never needed at all (not just
   deferred).
3. In parallel: the photo-gate `SELECT` (op 6) — still must complete+pass
   before writes.
4. Using the in-hand merged draft: `UPDATE user_profiles` (with the real
   `profile_complete_pct` computed **inline**, not a placeholder) + conditional
   astrology/partner-pref writes, all in one parallel batch.
5. **Skip `markComplete` (op 10) for this endpoint** — reachable only when
   already `true`. *(Explicit behavior-scoping decision — needs sign-off.)*
6. Compute `profile_complete_pct` **before** the write using the photo count
   already known + a combined existence check for astrology/partner-pref
   (or their write result if this call touched them) — eliminates op 13's
   separate correction write entirely.
   - ⚠️ Caveat: if the edit-mode response needs full `partnerPreference`/
     `astrology` objects (not just existence booleans), those still need a
     real read when not written this call — needs confirming against actual
     frontend consumption before trimming.

| | Before | After (C) |
|---|---|---|
| HTTP requests | 2 | **1** |
| Total DB round trips | 13 | **~5–6** |
| Sequential stages | 10 | **~3** |
| **Estimated Continue → Discover** | ~3.0–3.3s | **~1.0–1.3s** |

Files: new route + substantial refactor in `profile.service.ts` /
`profile.repository.ts`, plus **frontend** rewiring of
`_saveAndFinalizeForEdit()`. CREATE-mode paths untouched (separate endpoint).
Risk: highest — new raw SQL, a rewritten completion-calc ordering that must
be proven equivalent to `calculateCompletion()`'s existing output for every
section combination, and the `markComplete`-skip scoping decision. API
contract: yes (new route). Schema: none required.

**Honest caveat on Option C:** ~0.8–0.9s is the optimistic pure-DB-time case
(3 tight stages at exactly 255ms, zero contention). Real measured RTTs
ranged 250–320ms with occasional cold-pool spikes, plus Firebase's own
token-verify is external network and untouched by any of this. **~1.0–1.3s
is the honest estimate — likely close to, but not guaranteed under, 1
second.**

### Summary

| | A | B | C |
|---|---|---|---|
| Continue→Discover estimate | ~2.5–2.8s | ~1.9–2.2s | ~1.0–1.3s |
| Contract change | No | Yes (optional field) | Yes (new route) |
| Schema change | No | No | No |
| Frontend change | No | Yes | Yes |
| Risk | Very low | Moderate | High |

**Status: none approved yet.** Waiting on a decision before any of A/B/C is implemented.

---

## 8. Files touched in this round

- `backend/apps/api/src/modules/profiles/services/profile.service.ts` — the
  2 read eliminations (§2).
- `backend/apps/api/src/modules/profiles/tests/profile.service.spec.ts` —
  updated mocks to match (`findAllForUser` instead of `countForUser` for the
  photo gate).
- `docs/registration/edit-mode-continue-performance.md` — this doc.

Not touched: `profile.repository.ts`, `photo.repository.ts` (read, not
edited — `countForUser` is still used elsewhere by `photo.service.ts`'s
upload-limit check, so it was not removed from the repository, only from
`profile.service.ts`'s call site).

## 9. How to reproduce the real-device measurement

1. Rebuild + restart backend: `cd backend && npm run build:api && node
   --enable-source-maps dist/apps/api/main` (fresh process = cold pool, so
   expect test 1 to be slower than tests 2/3 — that's expected, not a bug).
2. Connect an Android phone via USB with debugging enabled/authorized.
3. `adb reverse tcp:3000 tcp:3000` (or run
   `scripts/dev/setup_android_usb.bat`).
4. `adb logcat -c && adb logcat | grep STORY-PERF` in one terminal.
5. On the phone: drawer → Edit Profile → change any field → Continue → wait
   for the "Profile updated successfully" snackbar and the Discover screen.
6. Read `PATCH response received`, `finalize started`/`finalize response
   received`, and `Next registration page rendered` (after `Navigation
   started (to discover)`) from the `[STORY-PERF]` lines — all are
   ms-since-`Continue tapped` (each cycle resets to `0ms`).
7. Cross-check against the backend's own `[STORY-PERF-SRV]` epoch-ms
   timestamps for the same window if you want DB-side stage breakdown.
