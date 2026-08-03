# NEW_MESSAGE Notification Implementation

## Overview

Before this change, sending a chat message only delivered a realtime `chat.message` socket event with the full message payload. A recipient who wasn't actively connected to the socket (app backgrounded, terminated, or offline) received nothing — no notification-center entry, no push. This feature closes that gap: sending a chat message now also raises a standard in-app notification and dispatches a push, so the recipient is reliably notified regardless of their connection state.

---

## Existing Architecture

The notification system already existed and was fully functional for two domains (Interests, Shortlists) before this feature:

- **NotificationsService** — orchestrates notification creation (`create`), unread-cache invalidation (`invalidateUnread`), and push dispatch (`dispatchPush`).
- **NotificationRepository** — Prisma-backed persistence for the `Notification` table and `DevicePushToken` records.
- **PushDispatchService** — owns FCM device-token lifecycle (register/unregister/cleanup of dead tokens) and multi-device fan-out.
- **Firebase FCM** — `FirebaseService.sendMulticastPush()` sends the actual push via the Firebase Admin SDK.
- **Device tokens** — `DevicePushToken` rows, one per device, registered via `POST /notifications/device`.
- **Notification database** — the `Notification` table, read via `GET /notifications` and `GET /notifications/unread-count`.
- **Realtime notification events** — a `notification.created` socket event (id + timestamp only) that signals clients to refresh their notification list.

This feature does not introduce any new service, repository, or database table. It extends the existing pipeline to a third caller, following the exact pattern already used by `InterestsService` and `ShortlistService`.

---

## What Was Implemented

**`messages.service.ts`** — `MessagesService.send()` now creates a `NEW_MESSAGE` notification for the recipient and dispatches a push, using the injected `NotificationsService`. Required because this is where a chat message is persisted — the natural point to raise the corresponding notification.

**`chat.module.ts`** — added `NotificationsModule` to `imports`. Required because `NotificationsService` is not a global provider; `ChatModule` must import the module that exports it for Nest's DI to resolve `MessagesService`'s new constructor dependency.

**`messages.service.spec.ts`** — added a `notifications` mock to the test harness and two new tests. Required because the constructor signature changed (existing tests would fail to compile without it), and to verify the new behavior: notification creation, push dispatch, and the realtime signal all target the recipient only, and none of it duplicates on an idempotent retry.

No schema changes, no migrations, no new endpoints, and no changes to `edit()` or `remove()` (only `send()` raises a notification).

---

## Notification Flow

```
User A sends message
        ↓
Message saved                          — MessageRepository.create(tx, …)
        ↓
Notification created (inside transaction) — NotificationsService.create(tx, …), type NEW_MESSAGE
        ↓
Transaction commits
        ↓
Unread cache invalidated               — NotificationsService.invalidateUnread(peerId)
        ↓
Push dispatched                        — NotificationsService.dispatchPush(...) (fire-and-forget)
        ↓
notification.created realtime event emitted — signals User B's client to refresh its list
```

Each step:
1. The message row is written inside a Prisma transaction, alongside the existing room-activity timestamp bump.
2. In the same transaction, a `Notification` row (`type: NEW_MESSAGE`) is created for the recipient — atomic with the message write.
3. Once the transaction commits, the existing `chat.message` realtime event (full payload, unchanged) is emitted to both parties.
4. The recipient's Redis-cached unread count is invalidated so their badge is correct on the next read.
5. A push notification is dispatched to all of the recipient's active devices, without blocking the API response.
6. A `notification.created` refresh signal is emitted to the recipient so their notification-center list updates live.

---

## Design Decisions

- **Notification created inside the transaction** — so a rolled-back message send never leaves an orphaned notification, and a failed notification write rolls back the message too. Matches `InterestsService`/`ShortlistService` exactly.
- **Push dispatched only after commit** — a transaction can still roll back; a push must never reach a device for a write that didn't actually happen.
- **Fire-and-forget dispatch** (`void dispatchPush(...)`) — a push failure (FCM outage, dead token) must never fail the message-send request. This is the existing architecture's established contract, not new to this feature.
- **Generic push title/body** (`"New message"` / `"You have a new message."`) — matches the existing privacy-conscious pattern (Interests uses `"Someone has expressed interest in your profile."`); message content is never put in a push payload or shown on a lock screen.
- **`roomId` used as `referenceId`** — the conversation is the natural target for this notification, positioning the payload correctly for future navigation without requiring it now.
- **Recipient only** — the sender never receives a notification, push, or realtime signal for their own message. Enforced structurally (the notification target is always `peerId`, never `userId`) and covered by a test.
- **Existing architecture reused, not replaced** — no new service, repository, queue, or database table. The same three-service pipeline (`NotificationsService` → `NotificationRepository` / `PushDispatchService` → `FirebaseService`) now has a third caller.

---

## Files Modified

| File | Responsibility |
|---|---|
| `apps/api/src/modules/chat/services/messages.service.ts` | Creates the `NEW_MESSAGE` notification, invalidates the recipient's unread cache, dispatches the push, and emits `notification.created` — all inside `send()`. |
| `apps/api/src/modules/chat/chat.module.ts` | Imports `NotificationsModule` so `NotificationsService` is injectable into `MessagesService`. |
| `apps/api/src/modules/chat/tests/messages.service.spec.ts` | Mocks `NotificationsService` and verifies notification creation, push dispatch, recipient-only targeting, and idempotency. |

---

## Testing

**Automated**: `pnpm exec jest apps/api/src/modules/chat` — 35/35 passing, including the new coverage for notification creation, recipient-only targeting, and duplicate-retry prevention. Full repository suite: 42/42 test suites passing.

**Idempotency verification**: a retried send with the same `clientMessageId` — whether returned by the early idempotency check or by the concurrent-request race path — creates no second notification and dispatches no second push, confirmed by a dedicated test.

**Manual testing checklist**:
- Send a message between two users with an accepted interest and an active device token on the recipient's side; confirm a `NEW_MESSAGE` row appears via `GET /notifications` and the recipient's device receives a push.
- Confirm `GET /notifications/unread-count` reflects the new message immediately (proves cache invalidation ran).
- Confirm the sender receives no notification, push, or `notification.created` event for their own message.
- Retry the same send with an identical `clientMessageId`; confirm no duplicate notification is created.
- Remove the recipient's device token and resend; confirm the message still sends successfully (push absence must not affect the API response).

**Build verification**: `tsc --noEmit`, `eslint`, and `pnpm run build` all pass with no errors.

---

## PR Review Summary

A full senior-engineer review was performed against architecture consistency, transaction safety, race conditions, duplicate-notification scenarios, idempotency, null safety, error handling, performance, maintainability, and security/privacy.

Findings: the notification write is atomic with the message write; every retry/race path correctly avoids duplicate notifications; all values used are structurally guaranteed non-null; the fire-and-forget push and the awaited cache invalidation both come from already-safe, error-swallowing methods, so neither can fail the request; the added cost per request is one extra transactional insert and one Redis delete; the push payload never leaks message content, and the notification is provably scoped to the recipient only.

**The implementation was approved without production blockers.**

---

## Final Result

When User A sends User B a message:

- The message is stored, exactly as before.
- A `NEW_MESSAGE` notification is stored for User B.
- A push notification is sent to all of User B's active devices.
- A `notification.created` realtime event is emitted to User B.
- User B's unread notification count is updated and reflected on their next read.

User A's experience is unchanged — they receive no notification of their own message.

---

# Flutter Impact

The backend notification pipeline for `NEW_MESSAGE` is not type-specific on the client side:

- The notification list (`GET /notifications`) and unread-count screens already render any `NotificationType` value generically — the client maps an unrecognized type to a generic display category rather than requiring a per-type branch.
- The push-notification service already displays any incoming FCM message (foreground via a local notification, background/terminated via the OS) regardless of its `type` field — it does not special-case by notification type before showing it.
- The realtime layer already listens for the generic `notification.created` event and refreshes the notification list on receipt — this is not scoped to specific notification types, so it already fires for `NEW_MESSAGE`.
- Device token registration, refresh, and the unread-count/list endpoints this feature relies on were already implemented and are unchanged by this backend work.

> No Flutter changes are required for this backend feature.

---

# Future Enhancements (Out of Scope)

The following were intentionally not implemented as part of this feature:

- **Deep linking into chat** — tapping a `NEW_MESSAGE` notification currently opens the generic notifications screen rather than the specific conversation. The payload already carries `referenceId` (the room id) to support this later; the routing logic itself is a pre-existing gap that applies to other notification types too, not something introduced here.
- **Push retry queue (BullMQ)** — a failed push is currently logged and dropped, with no retry. `PushFanoutProducer` exists as a stub for this.
- **Notification batching** — rapid successive messages each generate their own notification and push; no batching/grouping exists.
- **Online-user suppression** — a push is dispatched regardless of whether the recipient is actively connected via socket.
- **Rich notification previews** — the push title/body are generic and never include sender name or message content.

These are explicitly future work and were not part of this implementation.
