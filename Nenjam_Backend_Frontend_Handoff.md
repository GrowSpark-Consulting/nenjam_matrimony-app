# Nenjam Matrimony — Backend / Frontend Engineering Handoff

**Status:** Final handoff following completion of the frontend audit
**Audience:** Backend engineers, product owner
**Scope:** Flutter client (`Frontend/`) ↔ NestJS API (`backend/`)

> **Revision — verified against `main` after PR #79 (`feat/premium-privacy`) and PR #80 (`fix/preference-scoring`).**
> Premium has moved from *unimplemented* to **partially implemented**, and a new **Privacy / photo visibility** capability shipped fully wired on both sides. Section 3.1 and the Premium checklist have been rewritten accordingly; counts in Sections 1 and 9 are recalculated. The four backend fixes in Section 2 were each re-verified and **all four still stand unchanged**.

---

## Section 1 — Executive Summary

The **frontend audit is complete**. Every confirmed frontend defect identified during the audit has been fixed, verified by targeted tests, and closed. **Zero frontend audit fixes remain outstanding.**

What remains is not frontend work. It falls into three buckets:

| Category | Count | Nature |
|---|---|---|
| **Backend fixes required** | **4** | Concrete defects or missing contract fields in existing backend code |
| **Backend / product features partially implemented** | **1** | Premium — full read path built; no write path to create the data |
| **Backend / product features not implemented** | **6** | Capabilities that have never been built |
| **Shipped since the original audit** | **1** | Privacy / photo visibility — wired end to end |
| **Intentionally deferred** | **2** | Awaiting a product decision or a prerequisite switch |

A recurring theme runs through this document and is important to internalise before reading further:

> **In almost every remaining area, the frontend is already written, already correct, and already waiting.** Models map the fields. Widgets gate on the values. Tests assert the non-placeholder cases. The day the backend sends a real value, it flows through to the UI **with no client release required.**

This is deliberate. During the audit, several findings looked like frontend bugs but turned out to be the frontend faithfully reflecting a backend placeholder or an absent contract. In those cases **no frontend change was made**, because a client-side workaround would have been the wrong fix — it would have hidden the gap, duplicated storage, or risked breaking a working request.

**The guidance to backend is therefore: implement the contracts and features below rather than asking the frontend to compensate for their absence.**

---

## Section 2 — Backend Fixes Required Now

These are four discrete pieces of work against code that already exists. They are not new features.

---

### 2.1 — Partner Preferences: `extended` persistence

**Priority: HIGH** — this is the only item on this list causing active, silent data loss.

#### Current problem

The standalone Partner Preferences page (Edit Profile) saves through `PUT /discover/preferences`. That endpoint's DTO whitelists **13 base fields and does not include `extended`**.

The frontend collects **33 advanced preference fields** under `extended` (community, education/career, family, lifestyle, location, acceptance, verification, plus a per-field importance map). The registration draft path **already persists these correctly** — the draft DTO declares `extended?: Record<string, unknown>` and the value lands in the `partner_preferences.extended_preferences` column.

The standalone page does not. The result:

- A member edits advanced preferences on the Edit Profile page.
- They tap Save and see a success confirmation.
- The **base fields save correctly**; the advanced fields are **never sent anywhere**.

The frontend cannot fix this unilaterally. The API runs with `forbidNonWhitelisted: true`, so sending `extended` to the current DTO would **reject the entire request with a 400**, breaking base-field saving that works today. The client correctly sends only what the endpoint accepts.

**The supporting infrastructure already exists.** The database column, the entity field, and every consumer (`feed.repository.ts`, `partner-preference-where.builder.ts`, `preference-compatibility.signal.ts`, which reads diet/smoking/drinking for scoring) are all in place and in use via the draft path.

#### Backend work required

- Add to `backend/apps/api/src/modules/matches/dto/partner-preference.dto.ts`:
  ```ts
  @IsOptional()
  @IsObject()
  extended?: Record<string, unknown>;
  ```
- Persist `extended` to the existing `extended_preferences` column.
- Return `extended` in the GET / response contract so the client can hydrate it.
- Preserve all existing base-field behaviour, including the partial-update semantics (an omitted field is untouched; an explicit `null` clears a saved limit).

#### Acceptance criteria

- Extended preferences are accepted by the standalone `PUT`.
- Extended preferences are persisted.
- Extended preferences are returned by the `GET` / response.
- Existing base preferences still save correctly, including the omit-vs-clear distinction.
- Existing registration draft behaviour is unchanged.

> **Re-verified after PR #80 (`fix/preference-scoring`) — this blocker still stands.**
> PR #80 added `matches/filters/preference-categories.ts`, which fixes how **base** preference values are *matched*: the preference picker offers categories ("B.E / B.Tech+", "Software / IT") while profiles store specific values ("B.E / B.Tech", "Software Engineer"), and because both contain "/", a generic group-label rule was dropping every one of them — so an education preference was **never applied, not even an exact match**. That is a genuine matching fix, and it is pinned by a spec that reads the Dart source and fails on drift.
>
> **It does not touch `extended`.** It concerns base-field *matching semantics*, not advanced-preference *persistence*. The `matches` partner-preference DTO was re-checked and still does **not** declare `extended`, so the standalone save path remains unable to persist advanced preferences. The §2.1 conclusion is unchanged.
>
> Note the distinction for the earlier statement that advanced preferences are "not persisted / not used": advanced preferences captured **during onboarding** *are* persisted (via the draft path) and *are* consumed by `preference-compatibility.signal.ts` for diet/smoking/drinking scoring. What is lost is edits made on the **standalone Edit Profile page**. PR #80 does not change either half of that.

---

### 2.2 — Gothra structured persistence

**Priority: MEDIUM / LOW**

#### Current problem

The frontend Gothra flow is **complete and correct end to end** — UI → model → `toJson()` → `PATCH` → response mapping → Edit Profile reload. The backend DTO accepts `gothra`, and finalize maps it to `AstrologyProfile.gotram`.

The gap is a conditional guard. In `backend/apps/api/src/modules/profiles/services/profile.service.ts`, the astrology upsert (which contains the `gotram` write) runs only when `hasHoroscopeData` is true:

```ts
const hasHoroscopeData = Boolean(
  horoscope.birthTime || horoscope.birthPlace || horoscope.rashi ||
  horoscope.nakshatra || horoscope.star || horoscope.horoscopeAvailable,
);
```

`religion.gothra` is **not** in that condition. A member who enters Gothra but leaves every horoscope field blank finalizes with `hasHoroscopeData === false`, the astrology upsert is skipped entirely, and **Gothra is never written to structured storage**.

There is also no read-back path: nothing maps `gotram` into the draft or profile response.

**Impact is limited.** The value survives in the `draft_data` JSON blob and reloads correctly in Edit Profile, so the member never sees it disappear. What is lost is *structured* storage — meaning `gotram` cannot be queried, matched on, or surfaced on a finalized profile for that cohort. This becomes material once horoscope matching starts reading it.

#### Backend work required

- Include `religion.gothra` in the `hasHoroscopeData` condition.
- Ensure structured `gotram` can be read back where the profile contract requires it.

#### Acceptance criteria

- Finalizing a profile with Gothra and **no** horoscope data creates/persists the structured `gotram` value.
- Existing horoscope-data behaviour is unchanged.
- Read-back returns the value wherever the profile contract requires it.

---

### 2.3 — Search server-side filtering

**Priority: MEDIUM / HIGH** — highest correctness impact of the four, and it worsens over time.

#### Current problem

`GET /discover/search` reads exactly three parameters: `q`, `page`, `limit`. It accepts no filter parameters.

The Search UI exposes roughly 25 filters. The frontend applies them **client-side, over results already fetched** — a deliberate, documented architecture given the endpoint's contract, not an oversight. Server-side membership is never re-litigated client-side: eligibility, blocks, suspended and incomplete profiles remain decided by `buildFeedWhere`, and client filtering only *narrows* what the server returned.

The consequence is stated plainly in the client code:

> *"filters apply to the pages loaded so far, not to the whole result set, so a restrictive filter can show few matches until more pages are loaded."*

So a member applying a restrictive filter combination may see "3 matches" — or none — when the true count across the eligible corpus is far higher. They would have to scroll and load further pages for more matches to surface. **This degrades as the member base grows**, which is the opposite of how it should age.

#### Backend work required

- Accept the Search filter parameters on `/discover/search`.
- Push filtering into the existing `buildFeedWhere` logic where appropriate — much of the predicate logic already exists there for the feed.
- Preserve existing eligibility / block / suspended / incomplete-profile filtering.
- Preserve correct pagination and `hasMore` behaviour.

#### Acceptance criteria

- Supported filters are enforced server-side.
- Filtering applies to the complete eligible result set, not only the loaded page.
- Pagination and `hasMore` remain correct.
- Existing query-only Search behaviour remains compatible (the client must be able to adopt filters incrementally).

---

### 2.4 — Missing Discovery feed fields (inert Search filters)

**Priority: MEDIUM / LOW**

#### Current problem

Five Search filters are collected by the UI and counted in the active-filter badge, but **cannot be evaluated against any profile**:

- `country`
- `state`
- `rashi`
- `star`
- `incomeVerified`

The reason was confirmed on both sides during the final sweep: **none of these fields exists on the Discovery profile response DTO, and none exists on the client entity.** Notably, `currentState` *is* read by the feed mapper but is **joined into the single `location` string** rather than exposed as a discrete field, so the client has nothing to compare against.

This is therefore **backend contract work, not frontend mapping work.** The client already documents the gap with an explicit `TODO(backend)` and deliberately does not apply these filters rather than silently mis-filtering.

**Impact:** the five filters change the badge count and can be "Reset", implying to the member that they are doing something. Rashi and star in particular carry real weight in this product.

#### Backend work required

- Expose the required fields in the Discovery profile response.
- Add the appropriate entity / query / mapper support.
- Make the values available for client-side filtering and/or the future server-side filtering in §2.3.
- Do not invent values — expose only what is genuinely stored.

#### Acceptance criteria

- Each of the five fields is available in the Discovery response.
- Values are correctly populated from real data.
- The frontend can consume them without client-side parsing hacks (e.g. splitting the `location` string).

---

## Section 3 — Backend / Product Features: Status

**These are not frontend bugs.** In each case the frontend mapping is already written and correct; the capability has simply never been built server-side (or, for Premium, is built but has no data). Where the backend currently sends a placeholder, the client renders it faithfully — which generally means showing nothing rather than showing something false.

**Status legend used below:**

| Marker | Meaning |
|---|---|
| ✅ **IMPLEMENTED** | Built and wired end to end, both sides |
| ⚠️ **PARTIALLY IMPLEMENTED** | Real code path exists, but a required piece is missing |
| ❌ **NOT IMPLEMENTED** | Never built; frontend maps a hardcoded backend placeholder |

---

### 3.1 — Subscription / Premium — ⚠️ **PARTIALLY IMPLEMENTED** (updated after PR #79)

> **This section was rewritten after PR #79.** The original handoff stated that `isPremium` was hardcoded `false` in the feed mapper. **That is no longer true** — the read path is now fully built and derives from real data. What remains missing is the *write* path: nothing creates the subscription rows it reads.

#### ✅ What is now implemented and wired

- **A single shared definition of "premium"** — `activePremiumSubscriptionWhere(now)` in `backend/libs/database/src/entitlements/premium-entitlement.ts`. A subscription counts only while `status = ACTIVE`, `startDate <= now < endDate`, and the plan is not `FREE`. It takes `now` as a parameter so every filter in one request evaluates against the same instant.
- **`EntitlementsModule`** (module / service / repository / specs) — **wired into the runtime graph** via `SettingsModule`, which is registered in `AppModule`. It is not imported by `AppModule` directly, but it *is* reachable.
- **The feed mapper no longer hardcodes the value.** It is now `isPremium: isPremiumMember(user)` (`profile-feed.mapper.ts:76`), reading a real `subscriptions` probe.
- **The feed query actually selects that probe** — `feed.repository.ts:126` spreads `photoPrivacySelectFor(viewerId, now)`, which includes a `take: 1` nested select filtered by `activePremiumSubscriptionWhere`. Notifications use the same probe.
- **A real privacy API** — `GET /settings` and `PATCH /settings/privacy`, returning `isPremium`, `hideMyProfile`, `hidePhotosFromNonConnections`, `profileVisibleToPremiumOnly`.

#### ❌ What is still missing

- **Nothing creates `UserSubscription` rows.** A repo-wide search for `userSubscription.create` / `.upsert` in application code returns **no hits** (only generated Prisma client boilerplate). Checkout, the Razorpay webhook, and the subscription module remain unimplemented stubs.
- The source states this plainly: *"nothing creates UserSubscription rows yet … so today this matches nobody and every member is treated as non-premium."*
- **Net runtime behaviour is unchanged:** `isPremium` still evaluates to `false` for every member — but now because there is no *data*, not because the value is faked.
- **One frontend own-profile hardcode remains:** `Frontend/lib/features/profile/presentation/pages/profile_page.dart:177` still passes `isPremium: false` with a `TODO(backend)`. The Discover/feed path is correct; this one screen is not.
- `ApiEndpoints.subscriptionStatus` still has **zero consumers** on the client.

#### Backend / product work remaining

- Implement checkout and the Razorpay webhook so `UserSubscription` rows are actually created.
- Implement the subscription module (currently a stub, still not in `AppModule`).
- No change needed to the entitlement rule, the feed probe, or the privacy API — those are done.

#### Frontend follow-up (later)

- Replace the `isPremium: false` hardcode at `profile_page.dart:177` once own-profile premium status is available.
- No change needed for the Discover/feed badge — the client already maps `isPremium` as a pass-through and will light up as soon as real rows exist.

---

### 3.1b — Privacy / photo visibility — ✅ **IMPLEMENTED** (new since the original audit)

Shipped by PR #79 and **wired end to end**; recorded here so it is not mistaken for outstanding work.

- **Backend:** `photo-visibility.ts` provides `photoPrivacySelectFor` (per-viewer probes as one `take: 1` nested select, so a page of 20 cards stays a single query), `arePhotosHidden`, and `isPremiumMember`. `hiddenFromDiscoveryWhere` hides premium members who enabled "Hide My Profile". `GET /settings` + `PATCH /settings/privacy` expose the settings.
- **Frontend:** `Frontend/lib/features/privacy/presentation/pages/privacy_page.dart` consumes both endpoints and correctly gates "Hide My Profile" behind `isPremium`.
- **Design note worth preserving:** `profileVisibleToPremiumOnly` was *repurposed* to mean "hide my profile" rather than adding a second overlapping flag. Hiding is premium-gated, so the flag alone is insufficient — a non-premium member stays visible even with it set.
- **Practical consequence today:** because no member can be premium (see §3.1), the hide-profile path is effectively inert until subscription rows exist. The photo-visibility gate for connections works independently of premium and is live.

**No frontend or backend work outstanding for this item.**

---

### 3.2 — Psychology module — ❌ **NOT IMPLEMENTED**

**Current state**

- **No Psychology backend module or controller exists at all** — confirmed by inspection of `AppModule` and the module tree. The client's `psychology/quiz/*` endpoint constants point at routes that do not exist.
- `psychologyMatchPercent` is hardcoded `0`.
- `isPsychologyCompleted` is hardcoded `false`.
- The frontend quiz runs entirely on an in-memory mock repository; `ApiPersonalityRepository` exists but is never wired.
- Quiz progress is transient by design: partial answers are lost on navigating away, and completed results survive navigation but not an app restart, because the mock holds them in an instance field.

**Backend / product work**

- Implement the Psychology API / module.
- Persist quiz responses and results.
- Provide completion state.
- Provide the compatibility score.
- **Define the persistence contract for partial vs. completed quiz state** — this decision determines whether the client needs any local draft storage at all.

**Frontend follow-up (later)**

- Swap the mock repository for the real API.
- Consume completion status and compatibility score.
- Revisit quiz progress persistence **according to the backend contract** — if partial responses persist server-side, no client-side draft storage is needed.

> **Note:** local draft storage was deliberately *not* added during the audit. Building it beneath a mock-backed feature whose completed results have nowhere to go would risk throwaway work and a migration. The `PsychologyQuiz` / `QuizQuestion` / `UserQuizResponse` Prisma models already exist, suggesting server-side storage is the intended home.

---

### 3.3 — Astrology engine — ❌ **NOT IMPLEMENTED**

**Current state**

- `astroMatchPercent` is hardcoded `0`. The backend comment is explicit about why: *"a score that silently means something different from its name is worse than a zero that plainly says 'not computed'."*
- `horoscopeAvailable` is hardcoded `false`.
- Frontend mapping is correct and faithful.
- The Discover **"Astro 0%" display bug has already been fixed** — the stat is now hidden when the score is 0, matching how the compatibility badge and horoscope section already gate the same value.

**Backend / product work**

- Implement astrology / horoscope functionality.
- Provide horoscope availability.
- Provide real astrology compatibility.
- Provide the required horoscope / Gothra data (see also §2.2).

**Frontend follow-up (later)**

- Consume real values.
- Verify the existing zero / unavailable gating still behaves correctly with real scores.
- Add contract / integration tests if required.

---

### 3.4 — Presence / Online status — ❌ **NOT IMPLEMENTED**

**Current state**

- `isOnline` is hardcoded `false` in the feed mapper.
- Frontend mapping is already correct.

**Backend work**

- Implement presence tracking.
- Provide reliable online / offline state.
- Expose it through the Discover / profile responses.

**Frontend follow-up (later)**

- Consume real `isOnline`.
- Verify existing badge / display behaviour.

---

### 3.5 — Daily Recommendations — ❌ **NOT IMPLEMENTED**

**Current state**

- No dedicated Daily Recommendations endpoint exists.
- The Matches reel **temporarily reuses the shared Discover feed** so the reel never shows an empty state. This is a documented interim behaviour with an explicit `TODO(backend)`, not a defect.

**Backend / product work**

- Define Daily Recommendations behaviour and selection logic.
- Implement the dedicated endpoint.
- Define pagination and refresh behaviour.

**Frontend follow-up (later)**

- Integrate the dedicated endpoint.
- Replace the interim feed source once the backend is ready.

---

### 3.6 — Profile analytics — ❌ **NOT IMPLEMENTED**

**Current state**

- `visibilityPct` is `0`.
- `responseTime` is `—`.
- Both carry a `TODO(backend)` noting that no analytics exist yet.

**Backend / product work**

- Implement profile visibility analytics.
- Implement response-time analytics.

**Frontend follow-up (later)**

- Consume real analytics and replace the placeholder display values through the existing contracts.

---

### 3.7 — Verification status — ❌ **NOT IMPLEMENTED**

**Current state**

- `/verification/status` remains a stub.
- The profile verification display reflects whatever the registration draft last echoed, defaulting to incomplete until the module ships.

**Backend / product work**

- Implement the verification status endpoint and its backing data.

**Frontend follow-up (later)**

- Consume real verification status in place of the draft echo.

---

## Section 4 — Frontend Work Already Completed

> ### `FRONTEND AUDIT FIXES REMAINING: 0`

Every item below was investigated and either **fixed and verified**, or **conclusively closed** with evidence that the frontend was already correct. None requires further attention.

- Onboarding draft persistence
- Delete Account / LocalAuthSession cleanup
- Router onboarding gate
- Duplicate onboarding gate
- Search dead filters
- Search cascading filters
- Height `6 ft 2 in+` handling
- Concurrent 401 refresh
- Profile display / copy ID behaviour
- Religion / community code preservation
- Dead `MatchesRepositoryImpl` removal
- Dead registration navigation / sync removal
- Search canonical option lists
- Discover `Astro 0%` display fix
- Discover envelope / cursor handling
- Pagination page vs. cursor behaviour
- Search filter persistence
- Empty Search result handling
- Profile gender mapping
- `CompatibilityEntity` mapping
- Badge field mapping
- Local session identifier freshness
- Registration snapshot route behaviour
- Psychology quiz progress investigation
- Gothra frontend flow
- Partner Preferences frontend contract
- Search client-side filtering
- OTP dummy-flow investigation
- S3 URL refresh / recovery investigation

A number of these closed as **"frontend already correct"** rather than as fixes — notably badge mapping, `CompatibilityEntity` mapping, the Gothra frontend flow, and the Partner Preferences frontend contract. In each case the apparent defect traced to a backend placeholder or an absent contract, and the correct action was to make **no** change. Those are the items now listed in Sections 2 and 3.

---

### Mandatory profile photo requirement (registration)

This was the most recent frontend production fix and is called out prominently here because it changes a hard registration gate that backend and QA both need to be aware of.

**Requirement:** a user must have **at least one profile photo** before continuing registration.

**Implemented:**

- Continue is disabled when the photo count is `0`.
- "Add later" / skip behaviour is **removed** from the photo step.
- `_next()` itself blocks continuation when there are zero photos (belt-and-braces alongside the disabled button).
- Registration draft routing includes the photo requirement.
- Resume / navigation cannot permanently bypass the photo step.
- Both uploaded photos and staged pending photos count toward the requirement.
- Deleting the only photo disables Continue again.
- Existing upload / reorder / delete / preview / verification behaviour is unchanged.

**Verification (as reported):**

- Dedicated photo requirement tests: **11/11 passed**
- Registration / profile-photo regression tests: **283 passed, 0 failed**
- Analyzer: **no issues**

**Known, accepted behaviour:** there can be one extra navigation tap after a post-OTP resume, because the synchronous draft gate cannot perform a network photo lookup before authentication completes. **This is acceptable and is not a correctness bug** — the gate still prevents completing registration without a photo.

---

## Section 5 — Frontend Follow-Up After Backend

> **These are FUTURE integration tasks, not current frontend bugs.**
> Nothing in this table is actionable until the corresponding backend contract or feature exists.

| Backend capability | Frontend follow-up |
|---|---|
| **Partner Preferences `extended`** | Send and receive `extended` on the standalone endpoint; persist and hydrate advanced preferences; add contract tests covering the whitelist boundary. |
| **Gothra structured read-back** | Consume the structured Gothra value; verify finalized-profile hydration. |
| **Search server-side filtering** | Send the newly supported filter parameters; adapt pagination **only if** the backend contract requires it. Add API contract / integration tests. |
| **Search feed fields** | Consume newly exposed `country`, `state`, `rashi`, `star`, `incomeVerified`; activate the five currently inert filters. |
| **Subscription / Premium** | Discover/feed badge needs **no change** — already a verified pass-through. Remaining: replace the `isPremium: false` hardcode at `profile_page.dart:177` once own-profile premium status exists. |
| **Privacy / photo visibility** | **None — already integrated** (`privacy_page.dart` consumes `GET /settings` + `PATCH /settings/privacy`). |
| **Psychology** | Replace the mock repository with the real API; consume completion status and compatibility score; implement quiz persistence **according to the backend contract**. |
| **Astrology** | Consume real horoscope availability and compatibility; verify existing zero / unavailable gating. |
| **Presence** | Consume real `isOnline`; verify badge behaviour. |
| **Daily Recommendations** | Integrate the dedicated endpoint; retire the interim shared-feed source. |
| **Analytics / Verification** | Consume real visibility, response time, and verification status in place of placeholders. |

> **`No frontend implementation is currently required for any of these until the corresponding backend contract/feature is available.`**

For several of these — particularly the badges, `isPremium`, `isOnline`, `horoscopeAvailable`, `isPsychologyCompleted`, and both compatibility scores — the "follow-up" may amount to **verification only**. The client already maps these fields as pass-throughs and its tests already assert the non-placeholder cases, so real values are expected to reach the UI without a code change.

---

## Section 6 — Intentionally Deferred

### 6.1 — S3 presigned image URL expiry

**Current state**

- Presigned URL TTL is **3600 seconds (1 hour)**; URLs arrive as plain strings with **no expiry metadata**.
- Existing recovery mechanisms: pull-to-refresh, cold start, realtime `feed.invalidate`, and profile edit/review refreshes.
- URLs are **never persisted to disk** — the image widget deliberately uses `Image.network` rather than a caching widget, precisely because these are short-lived presigned GETs against a private bucket. A cold start is therefore always clean.
- **Gap:** backgrounding the app for more than an hour and resuming can leave expired URLs rendering as placeholders until the member pulls to refresh.

**Do not implement automatically.** Two frontend approaches were evaluated and rejected during the audit:

- *Refresh on image load failure* — the error is undifferentiated, so a 403 expiry is indistinguishable from an offline device. This would fire a network refetch on every flaky-connection scroll.
- *Invalidate the feed on app resume* — plausible and architecturally consistent (the resume hook exists), but it refetches on **every** foreground including a brief app-switch, and gating it on elapsed time is an arbitrary polling heuristic. It also contradicts an existing tested contract that re-entering Discover does not refetch.

**Future decision required — one of:**

- A product decision on resume-triggered refresh, or
- Backend returns an `expiresAt` alongside `photoUrls` so the client can refresh deterministically, or
- Stable CDN URLs.

**Severity is low:** cosmetic, self-recovering with a single gesture, and never persisted.

> ⚠️ **Protect the current implementation.** If anyone later "optimises" the image widget to a disk-caching alternative, the cache would both miss constantly (the signature changes on every fetch) and risk persisting private-bucket content. The current `Image.network` choice is load-bearing until stable URLs exist.

---

### 6.2 — Real OTP

**Current dummy OTP behaviour remains unchanged and must not be altered.**

The audit examined the OTP flow for issues independent of real verification and found **no frontend bug that can safely be fixed today**:

- The un-awaited send call is benign — under the mock it is an explicit no-op, and under the real verifier `sendCode` reports failure through controller state rather than throwing, so there is no unhandled rejection.
- The verify loading state is correctly managed and guarded against re-entry.
- Back navigation via `PopScope` is correct, including the cold-start fallback.
- The hint text is already honest and makes no false "SMS sent" claim.
- There is no resend UI, correctly — resending a mock SMS is meaningless. Controller support (with a 60-second guard) already exists for when it is.
- An already-verified guard is currently **impossible**: dummy sessions mint no Firebase phone credential, so `phoneVerified` is structurally `false` for every such user. Gating on it would be meaningless.

**When real OTP is enabled, revisit:**

- `await` the send call
- Surface send failures to the user
- Send-phase loading indicator
- Already-verified guard
- Resend UI

**Do not implement now.** Each is cheap once real OTP is live and meaningless before then.

---

## Section 7 — Recommended Implementation Order

Ordered by **dependency and impact**, not by subjective score.

| # | Item | Type |
|---|---|---|
| 1 | Partner Preferences `extended` | Backend fix |
| 2 | Gothra structured persistence | Backend fix |
| 3 | Search server-side filtering | Backend fix |
| 4 | Search feed fields (country/state/rashi/star/incomeVerified) | Backend fix |
| 5 | Subscription / Premium — **checkout + webhook only** (read path already built, see §3.1) | Product feature (partial) |
| 6 | Psychology backend | Product feature |
| 7 | Astrology backend | Product feature |
| 8 | Presence | Product feature |
| 9 | Daily Recommendations | Product feature |
| 10 | Profile analytics / Verification status | Product feature |

**Why this order:**

**Items 1–4 are concrete backend fixes and contract additions.** They are small, well-understood, and operate on code and database columns that already exist. Each unblocks frontend behaviour that is already built and waiting. They should be completed first because they deliver the most correctness per unit of effort:

- **#1 first** — it is the only item causing active silent data loss, and the column, entity field, and consumers already exist. The draft path proves the shape works end to end.
- **#2 next** — a one-line condition change with a contained blast radius.
- **#3 then #4** — #3 has the largest correctness impact and degrades as the corpus grows. #4 can ship independently of #3, and doing so immediately activates five inert filters even before server-side filtering lands.

**Items 5–10 are product capabilities that have never been built.** They require design and product decisions, not just implementation, and each is substantially larger than items 1–4. Within this group, **#6 (Psychology)** is the largest — no backend module exists at all — and it blocks three separate client-side values (`psychologyMatchPercent`, `isPsychologyCompleted`, and the entire quiz feature).

---

## Section 8 — Backend Acceptance Checklist

### Partner Preferences
- [ ] `extended` accepted by standalone PUT
- [ ] `extended` persisted
- [ ] `extended` returned by GET
- [ ] Existing base fields still save

### Gothra
- [ ] Gothra-only profile finalization persists `gotram`
- [ ] Gothra read-back verified

### Search
- [ ] Search filter params accepted
- [ ] Server-side filtering implemented
- [ ] Pagination / `hasMore` remains correct
- [ ] `country` exposed
- [ ] `state` exposed
- [ ] `rashi` exposed
- [ ] `star` exposed
- [ ] `incomeVerified` exposed

### Premium *(partially complete — see §3.1)*
- [x] Shared premium-entitlement rule defined (`activePremiumSubscriptionWhere`)
- [x] `EntitlementsModule` reachable in the runtime graph (via `SettingsModule`)
- [x] Feed mapper derives `isPremium` from real data (no longer hardcoded)
- [x] Feed query selects the premium probe
- [ ] Checkout / Razorpay webhook create `UserSubscription` rows
- [ ] Subscription module implemented and registered in `AppModule`
- [ ] `isPremium` evaluates `true` for an actually-subscribed member
- [ ] Own-profile premium status available (unblocks `profile_page.dart:177`)

### Privacy / photo visibility *(complete — §3.1b)*
- [x] `GET /settings` / `PATCH /settings/privacy` implemented
- [x] Photo-visibility probes wired into feed and notifications
- [x] Frontend privacy page consumes both endpoints and gates on `isPremium`

### Psychology
- [ ] Backend module exists
- [ ] Quiz persistence exists
- [ ] Completion status available
- [ ] Compatibility score available

### Astrology
- [ ] Horoscope availability available
- [ ] Astrology compatibility available
- [ ] Required horoscope / Gothra data available

### Presence
- [ ] Online status available

### Daily Recommendations
- [ ] Dedicated endpoint available
- [ ] Recommendation selection logic implemented

### Analytics / Verification
- [ ] Visibility analytics available
- [ ] Response-time analytics available
- [ ] Verification status endpoint implemented

---

## Section 9 — Final Status

*Recalculated after PR #79 / PR #80.*

| | |
|---|---|
| **Frontend audit** | **COMPLETE** |
| **Frontend fixes remaining** | **0** (one deferred hardcode at `profile_page.dart:177`, blocked on backend) |
| **Backend fixes required** | **4** (all four re-verified as still standing) |
| **Backend / product features partially implemented** | **1** (Premium — read path done, write path missing) |
| **Backend / product features still incomplete** | **6** |
| **Shipped since the original audit** | **1** (Privacy / photo visibility) |
| **Deferred decisions** | **2** |

**Count reconciliation:** the original handoff listed **7** unimplemented features. Premium moved from *unimplemented* to *partially implemented*, leaving **6** genuinely unimplemented (Psychology, Astrology, Presence, Daily Recommendations, Profile analytics, Verification status). Total feature items remains 7; Privacy is tracked separately as newly shipped.

**The frontend should not create workarounds for missing backend contracts.**

Backend should implement the contracts and features documented above. Once each is available, the corresponding frontend follow-up item in Section 5 can be integrated and tested — and in several cases, no frontend change will be needed at all, because the client already maps the field and is simply waiting for a real value to arrive.
