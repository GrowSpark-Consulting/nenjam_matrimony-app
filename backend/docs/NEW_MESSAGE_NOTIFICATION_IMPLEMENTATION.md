# NEW_MESSAGE Notification Implementation

## Overview

Before this change, sending a chat message only delivered a realtime `chat.message` socket event with the full message payload. A recipient who wasn't actively connected to the socket (app backgrounded, terminated, or offline) received nothing — no notification-center entry, no push. This feature closes that gap: sending a chat message now also raises a standard in-app notification and dispatches a push, so the recipient is reliably notified regardless of their connection state.

> **Revision — WhatsApp-style previews.** This document originally described a privacy-first design in which both the push and the stored notification read `"New message"` / `"You have a new message."`, with message content never leaving the database. That decision has been **reversed**: notifications now carry the sender's display name as the title and the message text as the body, on both channels. Sections below reflect the current behavior; the superseded rationale is called out where it applied.

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

### Added by the preview revision

**`messages.service.ts`** — `send()` names `senderUserId`/`receiverUserId` explicitly, resolves the sender's display name before the transaction (via `Promise.all` alongside the existing presence read, so it costs no extra round trip), and builds one `title`/`body` pair that feeds both the stored notification row and the push. `dispatchNewMessagePush()` composes the push; `resolveSenderTitle()` resolves the name and swallows failures.

**`notifications.service.ts`** — `dispatchPush(data, options)` gained `excludeUserId` (forwarded to push dispatch) and `override` (push-only title/body/data). `resolveDisplayName(userId)` exposes the sender-name lookup.

**`push-dispatch.service.ts`** — `dispatchToUser(userId, payload, options)` gained `PushDispatchOptions.excludeUserId`, plus a guard that suppresses the send entirely when the recipient *is* the excluded actor.

**`notification.repository.ts`** — `findActiveTokensExcludingUser(userId, excludeUserId)` and `findDisplayName(userId)`.

**`push-dispatch.service.spec.ts`** (new) — six tests covering the exclusion logic.

Still no schema changes, no migrations, no new endpoints, and no queue changes.

---

## Notification Flow

```
User A sends message
        ↓
senderUserId / receiverUserId derived from the room row (never the request body)
        ↓
Sender display name + truncated body resolved  — Promise.all with the presence read
        ↓
Message saved                          — MessageRepository.create(tx, …)
        ↓
Notification created (inside transaction) — NotificationsService.create(tx, …), type NEW_MESSAGE
                                            title = sender name, body = message text
        ↓
Transaction commits
        ↓
Unread cache invalidated               — NotificationsService.invalidateUnread(receiverUserId)
        ↓
Push dispatched                        — dispatchNewMessagePush(...) (fire-and-forget)
                                            addressed to receiverUserId
                                            excludeUserId = senderUserId
        ↓
notification.created realtime event emitted — signals User B's client to refresh its list
```

Each step:
1. `senderUserId` is the authenticated caller; `receiverUserId` is the room's other participant, re-derived from the `ChatRoom` row.
2. The sender's display name and the 120-char truncated body are resolved up front — the notification row written inside the transaction now carries them, so they can no longer be looked up lazily after commit. Both lookups are issued alongside the existing presence read.
3. The message row is written inside a Prisma transaction, alongside the existing room-activity timestamp bump.
4. In the same transaction, a `Notification` row (`type: NEW_MESSAGE`) is created for the recipient — atomic with the message write, carrying the same title/body the push will use.
5. Once the transaction commits, the existing `chat.message` realtime event (full payload, unchanged) is emitted to both parties.
6. The recipient's Redis-cached unread count is invalidated so their badge is correct on the next read.
7. A push is dispatched to the recipient's active devices minus every device registered to the sender, without blocking the API response.
8. A `notification.created` refresh signal is emitted to the recipient so their notification-center list updates live.

---

## Design Decisions

- **Notification created inside the transaction** — so a rolled-back message send never leaves an orphaned notification, and a failed notification write rolls back the message too. Matches `InterestsService`/`ShortlistService` exactly.
- **Push dispatched only after commit** — a transaction can still roll back; a push must never reach a device for a write that didn't actually happen.
- **Fire-and-forget dispatch** (`void dispatchPush(...)`) — a push failure (FCM outage, dead token) must never fail the message-send request. This is the existing architecture's established contract, not new to this feature.
- ~~**Generic push title/body**~~ — **superseded.** The original design used `"New message"` / `"You have a new message."` on both channels, matching the privacy-conscious pattern Interests still uses (`"Someone has expressed interest in your profile."`). That is no longer the behavior: see **WhatsApp-style previews** below.
- **WhatsApp-style previews** — the title is the sender's display name and the body is the message text, truncated to 120 characters with the ellipsis inside that budget. Whitespace runs are collapsed so the body renders on one or two lines. This is a deliberate reversal of the privacy stance above: message content now appears on a lock screen and is persisted a second time in the `notifications` table. Media messages are the one exception — their stored content is a short-lived signed S3 URL, so they preview as `"Sent you an attachment."` instead.
- **One title/body pair for both channels** — the same resolved values are written to the notification row and passed as the push override, so the notification center and the lock screen can never disagree about what a message said. Covered by a test that asserts the two are identical.
- **Fallback title is the brand name, not `"New message"`** — a sender with no finalized `UserProfile` yields `"Nenjam"`. Reusing the old generic string here would make a fallback push indistinguishable from the fix not being deployed, which is precisely the ambiguity that made this hard to diagnose in the field.
- **Name lookup can never fail a send** — `resolveSenderTitle()` swallows every error and returns the fallback. Unlike the original post-commit lookup, it now runs *before* the transaction, so an unhandled rejection would fail the message send itself.
- **`roomId` used as `referenceId`** — the conversation is the natural target for this notification, positioning the payload correctly for future navigation without requiring it now.
- **Recipient only, with the sender's devices explicitly excluded** — the push is addressed to `receiverUserId`, and `excludeUserId: senderUserId` removes every token registered to the sender (active *and* inactive) before the send. Addressing alone is not sufficient: `fcmToken` is globally unique, so one physical device is a single row that gets *retargeted* between accounts. A shared/handed-over phone, an account switch, or a logout whose token cleanup never landed leaves a row pointing at the recipient while the sender is the one holding the device — which is how a sender ends up notified of their own message. Both layers are covered by tests.
- **Existing architecture reused, not replaced** — no new service, repository, queue, or database table. The same three-service pipeline (`NotificationsService` → `NotificationRepository` / `PushDispatchService` → `FirebaseService`) now has a third caller.

---

## Files Modified

| File | Responsibility |
|---|---|
| `apps/api/src/modules/chat/services/messages.service.ts` | Creates the `NEW_MESSAGE` notification, invalidates the recipient's unread cache, dispatches the push, and emits `notification.created` — all inside `send()`. Owns the title/body pair, the truncation helper, and the sender-name fallback. |
| `apps/api/src/modules/chat/chat.module.ts` | Imports `NotificationsModule` so `NotificationsService` is injectable into `MessagesService`. |
| `apps/api/src/modules/chat/tests/messages.service.spec.ts` | Mocks `NotificationsService` and verifies notification creation, push dispatch, recipient-only targeting, idempotency, preview content, truncation, and stored-vs-pushed parity. |
| `apps/api/src/modules/notifications/services/notifications.service.ts` | `dispatchPush` options (`excludeUserId`, `override`); `resolveDisplayName`. |
| `apps/api/src/modules/notifications/services/push-dispatch.service.ts` | `PushDispatchOptions.excludeUserId`; recipient-is-excluded-actor suppression guard. |
| `apps/api/src/modules/notifications/repositories/notification.repository.ts` | `findActiveTokensExcludingUser`, `findDisplayName`. |
| `apps/api/src/modules/notifications/tests/push-dispatch.service.spec.ts` | Exclusion logic: token subtraction, empty-result short-circuit, self-suppression, dead-token cleanup, never-throws. |
| `apps/api/src/modules/notifications/tests/notifications.service.spec.ts` | `dispatchPush` recipient addressing and option forwarding. |

---

## Testing

**Automated**: `pnpm exec jest apps/api/src/modules/chat` — 48/48 passing, including coverage for notification creation, recipient-only targeting, sender-device exclusion, preview content, 120-char truncation, stored-vs-pushed parity, media previews, name-lookup failure, and duplicate-retry prevention. Full repository suite: 50/50 test suites, 420 passing.

**Idempotency verification**: a retried send with the same `clientMessageId` — whether returned by the early idempotency check or by the concurrent-request race path — creates no second notification and dispatches no second push, confirmed by a dedicated test.

**Manual testing checklist**:
- Send a message between two users with an accepted interest and an active device token on the recipient's side; confirm a `NEW_MESSAGE` row appears via `GET /notifications` and the recipient's device receives a push.
- Confirm the push title is the **sender's name** and the body is the **message text** — not `"New message"`. A title of `"Nenjam"` means the sender has no finalized `UserProfile`; a title of `"New message"` means the running build predates this change.
- Confirm `GET /notifications` shows the same title and body as the push (they are written from one pair).
- Send a message longer than 120 characters; confirm both the push body and the stored row are cut to exactly 120 including the trailing `…`.
- Send an image; confirm both read `"Sent you an attachment."` and never a signed S3 URL.
- Confirm `GET /notifications/unread-count` reflects the new message immediately (proves cache invalidation ran).
- Confirm the sender receives no notification, push, or `notification.created` event for their own message.
- **Sign both accounts into the same physical device in turn, then message between them** — confirm the sender's device receives nothing. This is the case token addressing alone does not cover.
- Retry the same send with an identical `clientMessageId`; confirm no duplicate notification is created.
- Remove the recipient's device token and resend; confirm the message still sends successfully (push absence must not affect the API response).

**Build verification**: `tsc --noEmit`, `eslint`, and `pnpm run build` all pass with no errors.

---

## PR Review Summary

A full senior-engineer review was performed against architecture consistency, transaction safety, race conditions, duplicate-notification scenarios, idempotency, null safety, error handling, performance, maintainability, and security/privacy.

Findings: the notification write is atomic with the message write; every retry/race path correctly avoids duplicate notifications; all values used are structurally guaranteed non-null; the fire-and-forget push and the awaited cache invalidation both come from already-safe, error-swallowing methods, so neither can fail the request; the added cost per request is one extra transactional insert and one Redis delete; ~~the push payload never leaks message content~~, and the notification is provably scoped to the recipient only.

**The implementation was approved without production blockers.**

### Preview revision — open items

The finding struck through above no longer holds. Two consequences were accepted knowingly and remain open:

- **Message text now appears on a lock screen**, visible to anyone holding the recipient's unlocked-screen device. There is no per-user setting to opt out of previews.
- **Message text is persisted a second time**, in `notifications.body`. It already lives in `chat_messages`, so this is not a new class of exposure, but the copy is **not covered by chat's soft-delete** — `MessagesService.remove()` scrubs the message, not the notification row's preview.

Also note that rows created before this revision retain the old generic text, so a notification list will show a mix until they age out.

---

## Final Result

When User A ("Asha Patel") sends User B the message `Hello`:

- The message is stored, exactly as before.
- A `NEW_MESSAGE` notification is stored for User B with `title: "Asha Patel"`, `body: "Hello"`.
- A push is sent to User B's active devices, minus every device registered to User A:

```json
{
  "notification": { "title": "Asha Patel", "body": "Hello" },
  "data": { "type": "chat", "conversationId": "conv-7f3a", "senderId": "u-asha" }
}
```

- A `notification.created` realtime event is emitted to User B.
- User B's unread notification count is updated and reflected on their next read.

User A's experience is unchanged — they receive no notification of their own message, on any device they are or ever were registered on.

---

# Flutter Impact

The backend notification pipeline for `NEW_MESSAGE` is not type-specific on the client side:

- The notification list (`GET /notifications`) and unread-count screens already render any `NotificationType` value generically — the client maps an unrecognized type to a generic display category rather than requiring a per-type branch.
- The push-notification service already displays any incoming FCM message (foreground via a local notification, background/terminated via the OS) regardless of its `type` field — it does not special-case by notification type before showing it.
- The realtime layer already listens for the generic `notification.created` event and refreshes the notification list on receipt — this is not scoped to specific notification types, so it already fires for `NEW_MESSAGE`.
- Device token registration, refresh, and the unread-count/list endpoints this feature relies on were already implemented and are unchanged by this backend work.

> No Flutter changes are required for this backend feature.

**Verified again for the preview revision.** `LocalNotificationService.show()` passes `notification.title` / `notification.body` straight through with no fallback strings of its own, so a richer payload renders with no client change. The `data` block changed from `{ type: 'NEW_MESSAGE', actorId, referenceId }` to `{ type: 'chat', conversationId, senderId }`; `navigateForNotificationData` resolves unknown type strings through a `_ =>` fallback to the notification center, and `NEW_MESSAGE` already took that same branch, so tap behavior is byte-for-byte unchanged. One forward-looking caveat: the payload no longer carries `actorId`/`referenceId`, so a future deep-link implementation must read `conversationId`.

---

# Future Enhancements (Out of Scope)

The following were intentionally not implemented as part of this feature:

- **Deep linking into chat** — tapping a `NEW_MESSAGE` notification currently opens the generic notifications screen rather than the specific conversation. The payload already carries `referenceId` (the room id) to support this later; the routing logic itself is a pre-existing gap that applies to other notification types too, not something introduced here.
- **Push retry queue (BullMQ)** — a failed push is currently logged and dropped, with no retry. `PushFanoutProducer` exists as a stub for this.
- **Notification batching** — rapid successive messages each generate their own notification and push; no batching/grouping exists.
- **Online-user suppression** — a push is dispatched regardless of whether the recipient is actively connected via socket.
- ~~**Rich notification previews**~~ — **implemented** by the preview revision; see the Design Decisions section.

These are explicitly future work and were not part of this implementation.

### Added by the preview revision

- **Per-user preview opt-out** — previews are on for everyone, with no setting to fall back to a generic title/body. `User` already carries privacy toggles (`profileVisibleToPremiumOnly`, `hidePhotosFromNonConnections`), so this would follow an established pattern.
- **Scrubbing notification previews on message delete** — `MessagesService.remove()` soft-deletes the message but leaves the copy in `notifications.body`.
- **Backfilling pre-revision rows** — existing rows keep the generic text. A backfill would have to re-join `chat_messages`, and rows whose message was since edited or deleted cannot be reconstructed faithfully.
- **A richer sender-name source** — `findDisplayName` reads `UserProfile.firstName + lastName` and falls back to `"Nenjam"`. `User` has no `displayName` or `username` column, and `email`/`phone` must never reach a lock screen, so there is no intermediate step available without a schema change.
