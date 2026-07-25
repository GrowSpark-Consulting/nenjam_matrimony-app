# Backend Handoff — Frontend Work of 2026-07-25

Scope of this note: everything currently sitting **uncommitted** in the working tree
(`git status` / `git diff --cached --stat` — 51 files, +3218/-462), what it needs from
the backend to go live, and a full inventory of backend functionality that is still
outstanding across the app (not just today's features).

All of today's work is **frontend-only**. Every new feature is built against a mock
repository and is fully usable/demoable right now with fake data. Nothing here required
a backend change, and nothing here is blocked — it's simply running on mocks until the
matching NestJS routes exist.

---

## 1. What shipped today (frontend)

### 1.1 Interests (send / receive / accept / decline / withdraw)
Full cross-screen system: Discover, Matches, Profile Detail, Inbox, and dedicated
Sent/Received screens all read from one shared Riverpod `InterestsNotifier`, so a
send/accept/decline/withdraw on any screen is instantly reflected everywhere else
(optimistic update + rollback on failure).

- New: `interest_button_copy.dart`, `interest_status_label.dart`, `interest_list_view.dart`
- Changed: `interests_repository.dart` (added `InterestRelationshipStatus` enum +
  `deriveRelationshipStatus()`, `sendInterest`, `withdraw`), `mock_interests_repository.dart`,
  `interests_provider.dart`, `interest_card.dart`, both Sent/Received pages

### 1.2 Notifications
Bell icon on Discover → full notification list (unread badge, mark-read, mark-all-read,
pagination-ready, empty/error/loading states).

- New: `notification_entity.dart`, `notification_model.dart`, `notification_mock_datasource.dart`,
  `notification_repository_impl.dart` (mock, wired), `notification_api_repository_impl.dart`
  (real HTTP client, **dormant** — not wired to any provider), `notification_providers.dart`,
  `notification_time_format.dart`

### 1.3 Shortlist
Every shortlist/bookmark button across Discover, Matches, Profile Detail, and Search
now reads/writes one shared `ShortlistNotifier`. Profile Drawer shows a live count.
Shortlisted Profiles page has real loading/error/empty states, pull-to-refresh, and a
working remove action.

- New: `mock_shortlist_repository.dart`, `shortlist_provider.dart`, `shortlist_toggle.dart`,
  `shortlisted_profile_card.dart`
- Changed: `shortlist_repository.dart` (added `add`), `shortlisted_page.dart`, `profile_card.dart`

### 1.4 Bug fixes (real-device issues found during testing)
- **Duplicate Hero tag crash**: Discover/Matches cards and Profile Detail were sharing one
  Hero tag (`profile-photo-<id>`) across simultaneously-mounted `IndexedStack` branches.
  Scoped tags per origin screen (`profile-photo-discover-<id>`, `profile-photo-matches-<id>`)
  now flow through `openProfileDetail(..., heroTag: ...)`.
- **Profile Detail shortlist button not responding**: the button was silently ignoring
  taps while the notifier's initial (mock-delayed) load was still in flight. Now shows a
  spinner and disables itself during that window instead of no-op'ing.
- **Still open, not resolved today**: a second real-device crash
  (`'!keyReservation.contains(key)': is not true` in `navigator.dart`) surfaced after the
  Hero fix. This is a router/Navigator page-key investigation, **frontend-only, no
  backend involvement**, and is still in progress — diagnostic logging is in place,
  waiting on the next device log capture. Flagging it here only so it isn't mistaken for
  a backend blocker; it isn't.

---

## 2. What the backend needs to build next (in priority order)

All three features below already have their **database tables live** — this is
NestJS controller/service work, not schema work. The frontend's dormant `*ApiRepositoryImpl`
classes already contain the exact request/response shapes expected; swapping the mock
provider for the real one is a one-line change once each route exists.

### 2.1 Interests — `backend/apps/api/src/modules/interests/`
Currently a 4-line empty stub (`InterestsController {}`, `InterestsService {}`) and
**is not even registered in `app.module.ts`** — zero routes reachable regardless of
stub content. Backs onto the already-migrated `ExpressInterest` table
(`senderId, receiverId, status, createdAt, respondedAt`, enum `PENDING/ACCEPTED/DECLINED`,
unique on `[senderId, receiverId]`).

Needed:
| Method | Path | Notes |
|---|---|---|
| GET | `/interests/received?page&limit` | array of `{ id, sentAt, status, profile: DiscoveryProfileDto }` |
| GET | `/interests/sent?page&limit` | same shape |
| POST | `/matches/interest` | body `{ profileId }` → create; reuses the existing Matches write endpoint (send) |
| POST | `/matches/interest` | body `{ interestId, accept }` → accept/decline (reuses same endpoint) |
| DELETE | `/interests/:id` | withdraw a pending **sent** interest (hard delete, not a status) |

Reference: `Frontend/lib/features/interests/data/repositories/interests_repository_impl.dart`
(full doc comment with exact JSON shapes), `Frontend/lib/features/interests/domain/repositories/interests_repository.dart`.

### 2.2 Notifications — `backend/apps/api/src/modules/notifications/`
Same situation: 4-line stub, not registered in `app.module.ts`. Backs onto the live
`Notification` + `DevicePushToken` tables.

Needed:
| Method | Path | Notes |
|---|---|---|
| GET | `/notifications?page&limit` | `{ items: [...], page, limit, total, hasMore }` |
| GET | `/notifications/unread-count` | `{ count }` |
| PATCH | `/notifications/:id/read` | mark one read |
| PATCH | `/notifications/read-all` | mark all read |

Reference: `Frontend/lib/features/notifications/data/repositories/notification_api_repository_impl.dart`.

### 2.3 Shortlist — `backend/apps/api/src/modules/matches/`
`MatchesController` (which is meant to own `/matches/shortlist`) is a 4-line stub and
**is not registered in `MatchesModule`** at all (only `DiscoverController` is). Backs
onto the live `Shortlist` table (unique on `[userId, targetUserId]`).

Needed:
| Method | Path | Notes |
|---|---|---|
| GET | `/matches/shortlist?page&limit` | bare array of `DiscoveryProfileDto` |
| POST | `/matches/shortlist` | body `{ profileId }` → add (no-op if already shortlisted) |
| DELETE | `/matches/shortlist` | body `{ profileId }` → remove |

Reference: `Frontend/lib/features/shortlist/data/repositories/shortlist_repository_impl.dart`,
`Frontend/lib/features/shortlist/domain/repositories/shortlist_repository.dart`.

**Cutover for all three**: once a route ships, swap the relevant `*RepositoryProvider`
override from the mock class to the `*ApiRepositoryImpl`/`*RepositoryImpl` class already
sitting dormant in `data/repositories/` — no other frontend change needed.

---

## 3. Full backend functionality inventory (beyond today's three)

`AppModule` currently only imports **`ProfilesModule`, `MatchesModule` (Discover/search/
preferences only), and `SettingsModule`**. Every other module below exists as scaffolding
in `backend/apps/api/src/modules/` but is **not imported into `AppModule`** — so none of
their routes are reachable in the running API at all, independent of how complete their
internal code is.

| Module | Status | Notes |
|---|---|---|
| `chat/` | Scaffolded, not wired | Conversations/messages controllers, services, repositories, entities all present as files but empty/stub bodies. Backs onto live `ChatRoom`/`ChatMessage`/`MessageReaction` tables. Needed for the Inbox "Messages" tab (currently the only Inbox tab with no real feature behind it). |
| `subscription/` | Scaffolded, not wired | Plans/checkout/Razorpay webhook controllers present, stub bodies. Backs onto live `SubscriptionPlan`/`UserSubscription`/`PaymentTransaction` tables. Needed for monetization. |
| `verification/` | Scaffolded, not wired | Document (income/asset/aadhaar/NRI) + face verification. Backs onto live `KycVerification`/`FaceVerification` tables. |
| `trust-score/` | Scaffolded, not wired | Backs onto live `TrustScoreLog` table. |
| `admin/` | Scaffolded, not wired | Moderation, user management, verification review. Backs onto live `AuditLog`/moderation tables. |
| `support/` | Scaffolded, not wired | FAQ + tickets. Backs onto live `SupportTicket` table. |
| `astro/` | Scaffolded, not wired | Horoscope compatibility (Prokerala integration). Backs onto live `HoroscopeMatch`/`AstrologyProfile` tables. |
| `interests/`, `notifications/`, `matches` (shortlist half) | Scaffolded, not wired | Covered in detail above (§2) — these three are the **immediate priority** since the frontend is already fully built and waiting on them. |

### AI-based recommendations — explicitly a planned future phase, not started
`backend/apps/api/src/modules/matches/recommendation/recommendation.service.ts` defines
the `RecommendationService` interface with this comment, written directly into the code:

> "Phase 2's `FilteredFeedStrategy` filters by partner preference ... a future
> `AiRecommendationStrategy` would return the same rows scored/ranked — same signature
> either way."

Current state: Discover's feed is served by `ProgressiveFallbackStrategy` — a
non-AI, rules-based tiered relaxation of partner-preference filters (tier 1 = exact
match on saved preferences, tiers 2–10 progressively relax fields when a tier returns
zero results). This is deliberately built behind a DI token
(`RECOMMENDATION_SERVICE`) specifically so an AI-ranked strategy can be swapped in later
as a one-line change in `matches.module.ts` — **no AI/ML ranking work has been started
yet**; today's feed is purely rule-based.

### Search
`search/` module (Elasticsearch-backed, `postgres-search.strategy.ts` also present as a
fallback) — appears implemented and wired via `MatchesModule`/`ElasticsearchModule`, not
a gap.

---

## 4. Suggested next-step order for the backend dev

1. **Interests + Notifications + Shortlist controllers** (§2) — highest leverage, frontend
   is 100% done and waiting, DB tables already exist, just needs controller/service/DTO
   implementation + registering the modules in `AppModule`/`MatchesModule`.
2. **Chat** — Inbox's "Messages" tab is the last major Inbox surface with no real backend.
3. **Verification + Trust Score** — needed for any trust/safety-gated features.
4. **Subscription** — needed before any paid-tier gating can go live.
5. **Admin + Support** — lower urgency, no user-facing frontend blocked on these today.
6. **AI recommendation strategy** — later-phase, replaces `ProgressiveFallbackStrategy`
   without touching Flutter or the controller, whenever ranking work is prioritized.
