# Interests, Shortlist & Notifications — Backend

Production backend for the three features whose Flutter UI already shipped
(against mocks). This document is the API reference, the frontend cutover guide,
and the architecture notes.

---

## 1. Frontend integration (one-line cutover per feature)

The endpoints below match the **dormant** `*ApiRepositoryImpl` / `*RepositoryImpl`
classes exactly. To go live, swap each mock provider for the real impl — nothing
else (Riverpod, widgets, routing, optimistic updates) changes.

| Feature | File | Change |
|---|---|---|
| Interests | `interests/presentation/providers/interests_provider.dart` | `interestsRepositoryProvider` → `InterestsRepositoryImpl(ref.watch(apiClientProvider))` |
| Shortlist | `shortlist/presentation/providers/shortlist_provider.dart` | `shortlistRepositoryProvider` → `ShortlistRepositoryImpl(ref.watch(apiClientProvider))` |
| Notifications | `notifications/presentation/providers/notification_providers.dart` | `notificationRepositoryProvider` → `NotificationApiRepositoryImpl(ref.watch(apiClientProvider))` |

All routes are behind `FirebaseAuthGuard` — the client's existing `AuthInterceptor`
already attaches the Firebase ID token, so no auth wiring changes.

---

## 2. API reference

Envelope: responses are the raw JSON below (the project has no response wrapper).
Errors follow Nest's default `{ statusCode, message, error }`, which the client's
`unwrapOrThrow` already understands. `page` defaults to 1, `limit` to 20 (max 100).

### Interests

| Method | Path | Body | Response |
|---|---|---|---|
| `POST` | `/matches/interest` | `{ profileId }` | `{ id, sentAt, status }` — sends |
| `POST` | `/matches/interest` | `{ interestId, accept }` | `{ id, sentAt, status }` — accept/decline |
| `GET` | `/interests/received?page&limit` | — | `[{ id, sentAt, status, profile }]` (sender's card) |
| `GET` | `/interests/sent?page&limit` | — | `[{ id, sentAt, status, profile }]` (receiver's card) |
| `DELETE` | `/interests/:id` | — | `204` — withdraw a pending sent interest |

`status` ∈ `"pending" | "accepted" | "declined"` (lowercase — matches Flutter's
`InterestStatus` enum names). `profile` is a full `DiscoverProfileDto` (same shape
as the Discover feed). `sentAt` is ISO-8601.

**Send business rules** (all enforced, atomic with the notification):
cannot send to self (400), to a deleted/unknown member (404), to a
suspended/deactivated/banned member (403), across a block either direction (403),
or before the sender's own profile is complete (403); a duplicate active interest
or a reverse active interest → 409. Re-sending after a **decline** is allowed
(resets to `PENDING`).

### Shortlist

| Method | Path | Body | Response |
|---|---|---|---|
| `GET` | `/matches/shortlist?page&limit` | — | `[DiscoverProfileDto]` |
| `POST` | `/matches/shortlist` | `{ profileId }` | `204` — add (idempotent) |
| `DELETE` | `/matches/shortlist` | `{ profileId }` | `204` — remove (idempotent) |

Cannot shortlist self (400) or an unavailable member (404). A blocked
relationship is softly skipped (no row, no notification, no error). Adding raises
a `SHORTLIST_ADDED` notification to the target.

### Notifications

| Method | Path | Response |
|---|---|---|
| `GET` | `/notifications?page&limit` | `{ items, page, limit, total, hasMore }` |
| `GET` | `/notifications/unread-count` | `{ count }` (Redis cached) |
| `PATCH` | `/notifications/read-all` | `204` |
| `PATCH` | `/notifications/:id/read` | `204` (404 if not yours) |

Item shape: `{ id, type, title, message, isRead, createdAt, actor: { id, name, photoUrl } | null, referenceId, metadata }`.
`type` is the raw backend enum (e.g. `INTEREST_RECEIVED`); the client maps unknown
values to a generic category, so new types never break the contract.

---

## 3. Architecture notes / key decisions

- **No schema redesign.** `ExpressInterest`, `Shortlist`, `Notification` and their
  enums already existed with the right FKs/uniques. One additive migration
  (`20260725100000`) adds composite `(<owner>, created_at)` indexes so the three
  paginated lists are served from a single index instead of a filter+sort.
  Create these `CONCURRENTLY` out-of-band at 10M+ rows.

- **Transactional consistency.** Interest send/respond and shortlist add run the
  domain write **and** the resulting notification in one `prisma.$transaction`
  (`NotificationsService.create` accepts the caller's `tx` client). The
  unread-count cache is invalidated only *after* commit — a rolled-back
  transaction never leaves a stale notification or cache.

- **Idempotency + race safety.** Every mutating action is guarded to converge:
  the `[senderId, receiverId]` / `[userId, targetUserId]` uniques plus
  status-conditional `updateMany`/`deleteMany` (`respondIfPending`,
  `deletePendingSent`) mean two concurrent duplicate actions produce one winner
  and a clean 409/404 for the loser. A `P2002` unique race is caught and mapped
  to the same result the sequential path returns.

- **Interest lifecycle & extensibility.** The frontend models a withdrawal as
  *deletion* (its `InterestStatus` has only pending/accepted/declined), so
  withdraw hard-deletes rather than introducing a `WITHDRAWN` status the client
  can't render — honoring "zero frontend change." `InterestStatus` remains
  additively extensible (`ALTER TYPE ... ADD VALUE`) if a future
  `EXPIRED`/`CANCELLED` state is needed, with no schema redesign.

- **Redis unread-count cache.** Key `notif:unread:{userId}`, 300s TTL as a
  self-healing backstop, invalidated eagerly on every count-changing event.
  Fail-open (same pattern as the auth-guard cache): a Redis miss/outage falls
  back to the authoritative DB count and never blocks a request.

- **No N+1.** List endpoints resolve all counterpart profiles / actor avatars for
  a page in **one** batched query, then map in memory. Interest/shortlist cards
  reuse `ProfileFeedMapper` + `FEED_PROFILE_SELECT`, so they're byte-identical to
  Discover cards and inherit its selective column projection.

- **Ownership / authz.** Every route is user-scoped from the verified Firebase
  token; mutations enforce ownership in the query `WHERE` (mark-read, withdraw,
  respond) rather than a separate fetch — no horizontal privilege escalation.

- **Module wiring (no cycles).** `NotificationsModule` (leaf) → exported to
  `InterestsModule` → exported to `MatchesModule`. `MatchesController` owns the
  write paths (`/matches/interest`, `/matches/shortlist`) the client targets and
  delegates to `InterestsService` / `ShortlistService`.

## 4. Verification

`nest build` ✓ · `jest` 39 suites / 235 tests ✓ (44 new) · `prisma validate` ✓ ·
`prisma migrate status` up-to-date ✓ · `flutter analyze` unaffected (no client
changes in this branch).
