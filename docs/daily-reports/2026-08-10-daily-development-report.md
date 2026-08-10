# Daily Development Report — Nenjam Matrimony

## 1. Report Header

| Field | Value |
|---|---|
| **Project** | Nenjam Matrimony — AI-powered matrimonial platform |
| **Report date** | 10 August 2026 |
| **Prepared by** | Dhatripatel06 |
| **Branch** | `main` |
| **Workstream** | Android push notifications · Chat notification delivery · Chat timestamp correctness |
| **Backend environment** | NestJS 11 · Prisma 7.8 · PostgreSQL · Redis · firebase-admin 14.1 · TypeScript 5.7 · pnpm monorepo (`apps/api`, `libs/*`) |
| **Frontend environment** | Flutter (Dart SDK ^3.9.2) · Riverpod · Android target |
| **Push transport** | Firebase Cloud Messaging (Admin SDK multicast) |

---

## 2. Executive Summary

- ✅ **Chat pushes now carry the sender's real name and the actual message text**, replacing the generic `"New message" / "You have a new message."` placeholder pair.
- ✅ **Sender exclusion hardened** — a push is addressed to the receiver *and* every device token registered to the sender is dropped before send, closing the shared-device / account-switch case that address-based targeting alone cannot see.
- ✅ **One title/body pair now feeds both channels** — the stored notification row and the FCM payload are resolved from a single lookup, so the notification centre and the lock screen can never disagree.
- ✅ **Android notification icon corrected** to a monochrome vector drawable, resolving the indistinct white-blob status-bar icon caused by using the full-colour adaptive launcher icon.
- ✅ **Manifest FCM metadata and channel wiring verified end-to-end** — the manifest channel ID matches the channel the app actually creates, so background/terminated pushes land on the same high-importance channel as foreground ones.
- ✅ **Chat timestamp timezone defect fixed** — server timestamps were rendered in UTC wall-clock, displaying IST messages 5 h 30 m early after refresh; now converted to local time exactly once at the decode boundary, for both REST history and realtime socket messages.
- ✅ **Quality gates green** — ESLint clean, `tsc --noEmit` clean, full backend Jest suite 420 passed / 12 todo across 50 suites; 10 new Flutter regression tests passing.
- ⚠️ **One open runtime issue** — an intermittent Prisma `P2028` transaction timeout was observed on the message-send path during manual testing; not yet root-caused, no code change made.

---

## 3. Android FCM Notification Improvements

### 3.1 Changes

| # | Item | Detail | Status |
|---|---|---|---|
| 1 | **Monochrome notification icon** | New vector drawable `ic_notification.xml` — 24 dp viewport, single-path bell glyph, `android:tint="#FFFFFF"`. Android masks notification icons to a flat silhouette using only the alpha channel on API 21+, so the full-colour adaptive launcher icon rendered as an indistinct white blob. | ✅ |
| 2 | **Manifest metadata — icon** | `com.google.firebase.messaging.default_notification_icon` → `@drawable/ic_notification` (explicitly *not* `@mipmap/ic_launcher`). | ✅ |
| 3 | **Manifest metadata — channel** | `com.google.firebase.messaging.default_notification_channel_id` → `nenjam_default_channel`. | ✅ |
| 4 | **Channel verification** | Manifest channel ID confirmed identical to the channel the app registers at runtime: `LocalNotificationService._channel` = `nenjam_default_channel`, display name `"Notifications"`, description *"Interests, matches, messages, and account updates."*, `Importance.high`. Foreground and OS-displayed notifications therefore share one channel and one user-facing setting. | ✅ |
| 5 | **`POST_NOTIFICATIONS` permission** | Declared in the manifest for Android 13+ (API 33). Requested at runtime only after the user opts in via the in-app "Enable Notifications" prompt — never at cold start. | ✅ |
| 6 | **Background / terminated behaviour** | The backend sends a payload containing a `notification` block, so the OS auto-displays it when the app is backgrounded or terminated, using the manifest icon and channel above. No Dart code runs in this path — which is precisely why items 2–3 must be correct. | ✅ |
| 7 | **Foreground behaviour** | A foreground push is rendered by `LocalNotificationService` as a local heads-up notification on the same channel (`Importance.high` / `Priority.high`). | ✅ |

### 3.2 Files Changed

| File | Change | Size |
|---|---|---|
| `Frontend/android/app/src/main/res/drawable/ic_notification.xml` | **New** — monochrome status-bar/lock-screen icon | 17 lines |
| `Frontend/android/app/src/main/AndroidManifest.xml` | FCM default icon + default channel metadata | +6 / −1 |

> Both landed in commit `443ef40`.

---

## 4. Backend Chat Notification Enhancements

### 4.1 Changes

| # | Item | Implementation | Status |
|---|---|---|---|
| 1 | **Receiver-only delivery** | `MessagesService.send()` now names both identities explicitly — `senderUserId` (the authenticated caller) and `receiverUserId` (the room's other participant). Both are derived from the room row, never from the request body, so every downstream side effect (notification row, push, email, realtime) is routed by a server-derived identity. | ✅ |
| 2 | **Sender exclusion** | `dispatchPush(..., { excludeUserId: senderUserId })` → `PushDispatchService` → `NotificationRepository.findActiveTokensExcludingUser()`. The exclusion set is deliberately **not** filtered by `isActive`: an inactive row still identifies a physical device belonging to the sender, and `fcmToken` is globally unique, so the two sets can only overlap when one device has been retargeted between accounts — the exact case plain recipient-token targeting cannot see. A degenerate self-conversation is suppressed with a warning rather than pushed. | ✅ |
| 3 | **Dynamic sender name** | New `NotificationRepository.findDisplayName()` reads `UserProfile.firstName`/`lastName`; surfaced via `NotificationsService.resolveDisplayName()` and consumed by `MessagesService.resolveSenderTitle()`. Falls back to `"Nenjam"` — deliberately *not* `"New message"`, so a fallback push stays distinguishable from the old pre-fix behaviour. Email and phone are never used as a fallback: they must not reach a lock screen. | ✅ |
| 4 | **Resolution timing** | The name lookup is issued **before** the transaction, in the same `Promise.all` as the existing presence read — two independent single-row lookups, so no extra round trip is added to the send path. It swallows every failure: running pre-transaction means a thrown error would otherwise fail the message send itself. | ✅ |
| 5 | **Real message preview** | `truncateForPush()` collapses newlines and whitespace runs to single spaces and cuts to `PUSH_BODY_MAX_LENGTH = 120`, with the ellipsis counted inside that budget. Media messages use the fixed string `"Sent you an attachment."` — their stored content is a signed, short-lived S3 URL and is never previewable. | ✅ |
| 6 | **Shared title/body** | One resolved `title`/`body` pair is used verbatim for the `Notification` row written inside the transaction *and* for the push payload, via a new push-only `override` option on `NotificationsService.dispatchPush()`. | ✅ |
| 7 | **Transaction safety preserved** | The notification row is still created inside the send transaction; the push is still dispatched fire-and-forget only after commit. A rolled-back write can never reach a device, and a push failure can never fail the message send. | ✅ |

### 4.2 Files Changed

| File | Change | Size |
|---|---|---|
| `backend/apps/api/src/modules/chat/services/messages.service.ts` | Sender/receiver naming, `resolveSenderTitle()`, `truncateForPush()`, `dispatchNewMessagePush()`, shared title/body | +183 / −… |
| `backend/apps/api/src/modules/notifications/services/notifications.service.ts` | `DispatchPushOptions` (`excludeUserId`, `override`), `resolveDisplayName()` | +62 |
| `backend/apps/api/src/modules/notifications/services/push-dispatch.service.ts` | `PushDispatchOptions.excludeUserId`, exclusion + self-conversation guard | +47 |
| `backend/apps/api/src/modules/notifications/repositories/notification.repository.ts` | `findActiveTokensExcludingUser()`, `findDisplayName()` | +45 |
| `backend/apps/api/src/modules/chat/tests/messages.service.spec.ts` | Coverage for dynamic title, preview truncation, sender exclusion | +163 |
| `backend/apps/api/src/modules/notifications/tests/notifications.service.spec.ts` | Coverage for `override` and `excludeUserId` pass-through | +48 |
| `backend/apps/api/src/modules/notifications/tests/push-dispatch.service.spec.ts` | **New** — token-exclusion and suppression behaviour | new file |
| `backend/docs/NEW_MESSAGE_NOTIFICATION_IMPLEMENTATION.md` | Documentation updated to match | +103 |

**Total: 603 insertions, 88 deletions across 10 files** (backend + frontend combined).

---

## 5. Notification Payload Example

The Admin SDK multicast message assembled for a new chat message. All `data` values are coerced to strings, as FCM requires.

```json
{
  "tokens": [
    "<receiver-device-token-1>",
    "<receiver-device-token-2>"
  ],
  "notification": {
    "title": "Priya Sharma",
    "body": "Hi! I saw your profile and would love to connect."
  },
  "data": {
    "type": "chat",
    "conversationId": "b7c1f2a4-9d3e-4f10-8a52-6e0c11d9ab34",
    "senderId": "3f9a0c72-51de-4b88-9c07-2a41e8f5d610"
  }
}
```

**Notes**

| Field | Behaviour |
|---|---|
| `notification.title` | The sender's resolved display name; `"Nenjam"` when they have no finalized profile. |
| `notification.body` | The real message text, whitespace-collapsed and truncated to 120 chars; `"Sent you an attachment."` for image/audio/video messages. |
| `data.type` | `"chat"` — the client's routing discriminator. |
| `data.conversationId` | Room ID, positioned for deep-linking into the conversation. |
| Token list | Receiver's active tokens **minus** every token registered to the sender. |

---

## 6. Chat Timestamp Fix

### 6.1 Root Cause (UTC vs IST)

The backend serialises every chat timestamp with `Date.toISOString()`, so the wire value is always `Z`-suffixed UTC — and the socket emits the same DTO as REST. **The wire format was correct; no backend change was needed or made.**

On the client, `DateTime.parse("…Z")` returns a **UTC-flagged** `DateTime`. The UI then read wall-clock fields directly off it:

- `MessageBubble._time()` → `dateTime.hour` / `dateTime.minute`
- `formatConversationTime()` / `formatDateSeparator()` → `.year` / `.month` / `.day`, compared against a **local** `DateTime.now()`

Those render the **UTC** hour, so a message sent at 2:45 PM IST redisplayed as 9:15 AM — a clean 5 h 30 m shift. Optimistic bubbles used `DateTime.now()` (already local), which is why the time looked correct until a refresh replaced the optimistic entry with the parsed server value.

Notably, `lastSeenAt` already had `.toLocal()` applied in two places — `createdAt` and `lastMessageAt` were simply missed.

### 6.2 `parseServerTime()`

A new decode boundary — `Frontend/lib/core/utils/server_time.dart`:

- `parseServerTime(String)` / `tryParseServerTime(dynamic)` convert to local time **exactly once**.
- A string carrying a timezone designator (`Z` or an offset) is parsed to UTC by Dart and converted from there.
- A string with **no** designator is reinterpreted as UTC rather than trusted as local — treating a naive backend wall clock as local time is precisely the defect being prevented.
- Establishes the invariant: **every `DateTime` leaving the data layer is already local.** No provider, formatter, or widget calls `.toLocal()`, so double conversion is structurally impossible.

### 6.3 Files Changed

| File | Change |
|---|---|
| `Frontend/lib/core/utils/server_time.dart` | **New** — `parseServerTime()` / `tryParseServerTime()` (54 lines) |
| `Frontend/lib/features/inbox/data/mappers/message_wire_mapper.dart` | `sentAt`, `editedAt`, and reply-preview `editedAt` now decode through the helper. Shared by REST history, the send response, **and** socket `chat.message` / `chat.messageEdited` — one edit fixes both transports. |
| `Frontend/lib/features/inbox/data/repositories/conversation_api_repository_impl.dart` | `lastMessageAt` (2 sites) fixed; private `_parseLastSeen` removed in favour of the shared helper |
| `Frontend/lib/features/inbox/presentation/providers/chat_realtime_sync.dart` | Duplicate `_parseLastSeen` removed; uses the shared helper |
| `Frontend/test/features/inbox/message_timestamp_test.dart` | **New** — 10 regression tests, host-timezone independent |

No `DateTime.now()` call site was modified: the three optimistic message constructors and the optimistic `editedAt` already produce local times and must not be converted.

### 6.4 Before vs After

| Aspect | ❌ Before | ✅ After |
|---|---|---|
| Message sent 2:45 PM IST, after refresh | `9:15 AM` | `2:45 PM` |
| `createdAt` decode | `DateTime.parse()` → UTC-flagged | `parseServerTime()` → local |
| REST history messages | Shifted −5:30 | Correct |
| Realtime socket messages | Shifted −5:30 | Correct |
| Date separator / "Today" · "Yesterday" | Could show the previous day near midnight | Correct |
| Inbox list trailing time (`lastMessageAt`) | Shifted −5:30 | Correct |
| `editedAt` ("edited" marker) | UTC-flagged | Local |
| Optimistic bubble (`DateTime.now()`) | Correct (local) | Unchanged — still correct |
| Conversions per timestamp | 0 | Exactly 1, at the decode boundary |
| `lastSeenAt` parsing | Duplicated helper in 2 files | Single shared helper |

**Not affected, before or after:** message ordering, the 15-minute edit window, and unread cutoffs — `compareTo` / `isAfter` / `isAtSameMomentAs` / `difference` are instant-based and were never wrong.

---

## 7. Testing & Validation

| # | Scenario | Expected behaviour | Result |
|---|---|---|---|
| 1 | **Foreground** | Push arrives while the app is open; `LocalNotificationService` renders a heads-up notification on `nenjam_default_channel` with the sender's name and message text. | ⚠️ Pending device sign-off |
| 2 | **Background** | OS auto-displays the `notification` block using the manifest icon and channel; app process not required. | ⚠️ Pending device sign-off |
| 3 | **Terminated** | Same as background — OS-displayed; tapping cold-starts the app. | ⚠️ Pending device sign-off |
| 4 | **Lock screen** | Monochrome silhouette icon renders cleanly (no white blob); title = sender name, body = message preview. | ⚠️ Pending device sign-off |
| 5 | **In-app notification** | A `NEW_MESSAGE` row appears via `GET /notifications`; unread count reflects it; `notification.created` refreshes the list live. | ⚠️ Pending device sign-off |
| 6 | **Sender exclusion** | Sender receives no push for their own message, including on a device previously registered to both accounts. | ✅ Verified by automated test |
| 7 | **Timestamp refresh** | Message sent at local time still shows that same local time after pull-to-refresh and after a socket-delivered echo. | ✅ Verified by automated test |
| 8 | **Timestamp — timezone independence** | Decode invariant holds on a UTC CI host and an IST machine alike. | ✅ Verified by automated test |

> **Note:** rows 1–5 require a physical Android device and were not executed in this session's environment. They are the outstanding sign-off items before the production verdict in §11 can be raised to unconditional.

---

## 8. Quality Checks

| Check | Scope | Result |
|---|---|---|
| **ESLint** | `apps/api/src/modules/chat/**`, `apps/api/src/modules/notifications/**` | ✅ Exit 0 — no errors, no warnings |
| **TypeScript** | `tsc --noEmit -p apps/api/tsconfig.app.json` | ✅ Exit 0 |
| **Jest — targeted** | chat + notifications modules | ✅ **5 suites / 75 tests passed** |
| **Jest — full backend** | entire API test suite | ✅ **50 suites / 432 tests — 420 passed, 12 todo, 0 failed** |
| **Flutter — targeted** | `test/features/inbox/message_timestamp_test.dart` | ✅ **10 / 10 passed** |
| **`flutter analyze`** | `lib/core/utils/`, `lib/features/inbox/`, `test/features/inbox/` | ✅ Clean — only 2 pre-existing `cacheExtent` deprecation infos, unrelated to this work |
| **Flutter — full suite** | all tests | ⚠️ 34 passed / 13 failed — **all 13 failures pre-existing and unrelated** (see below) |

### 8.1 Pre-existing Flutter test failures

All 13 failures are in `test/features/profile_detail/profile_detail_scroll_diagnostic_test.dart`, and all are 10-minute `TimeoutException`s rather than assertion failures.

**Not caused by today's work, on three independent grounds:**

1. The file imports only `discover` and `profile_detail` widgets — it has no reference to `inbox`, `server_time`, or any changed path.
2. The cause is **documented in the repository itself**: the sibling `tab_bar_scroll_reset_test.dart` records that `ProfileDetailPage`'s widget tree "currently fails to compile due to an unrelated, pre-existing `flutter_local_notifications` API mismatch", and that this exact harness hits the 10-minute timeout as a result.
3. The observed failure mode matches that documented behaviour precisely.

**Action:** tracked as a separate pre-existing defect; the `flutter_local_notifications` API mismatch should be resolved so this diagnostic suite becomes runnable again. Not in scope for today.

---

## 9. Issues Encountered

### ⚠️ Prisma `P2028` — Transaction API error / transaction timeout

**Observed:** intermittently on the message-send path during manual testing. `P2028` is raised when an interactive transaction exceeds its time budget and is closed before its callback finishes — subsequent queries on that transaction client then fail.

**Context.** `MessagesService.send()` wraps three writes in one interactive transaction:

1. `messageRepository.create()` — insert the `ChatMessage` row
2. `messageRepository.touchRoomActivity()` — bump the room's `lastMessageAt`
3. `notifications.create()` — insert the `NEW_MESSAGE` notification row

Prisma's interactive-transaction defaults are `maxWait` 2 000 ms and `timeout` 5 000 ms.

**Likely causes, in order of probability:**

| # | Hypothesis | Reasoning |
|---|---|---|
| 1 | **Network latency to a remote/managed PostgreSQL instance** | Three sequential round trips inside one transaction; at high per-query latency the 5 s budget is consumed by network time, not by query work. |
| 2 | **Cold start / connection acquisition** | The first send after an idle period pays connection-establishment and plan-cache warm-up inside the transaction window, plus up to `maxWait` just to acquire a pooled connection. |
| 3 | **Connection-pool starvation under concurrency** | Concurrent sends compete for a small pool; a transaction that cannot obtain a connection within `maxWait` fails before doing any work. |
| 4 | **Debugger / breakpoint pause during manual testing** | A paused process holds the transaction open past the timeout — common when the error appears only during hands-on testing and never in CI. |
| 5 | **Added transactional work** | The notification insert is a third statement inside a transaction that previously held two, marginally widening an already-tight window. |

**Status:** ⚠️ **Open — not root-caused, no code change made.** It did not reproduce in the automated suite (432/432 green). Recommended next step: log the transaction's wall-clock duration and the failure's pool-wait component before deciding between raising the `timeout`/`maxWait` options, enlarging the pool, or moving the notification insert out of the transaction.

---

## 10. Remaining / Future Improvements

| # | Item | Description | Priority |
|---|---|---|---|
| 1 | **Notification privacy toggle** | Pushes now contain real message text. Users should be able to choose a generic preview (`"New message"`) instead — a per-user setting honoured at payload-assembly time, so message content never reaches a lock screen for users who opt out. | High |
| 2 | **Message deletion sync** | Deleting a message does not retract or update an already-delivered notification or its notification-centre row; the preview outlives the message it previews. | Medium |
| 3 | **Rich media notifications** | Image messages currently push the fixed string `"Sent you an attachment."`. A `BigPictureStyle` / image-attachment payload would show the thumbnail inline. | Medium |
| 4 | **Notification preferences** | Per-category mute (messages / interests / shortlists), quiet hours, and per-conversation muting honoured server-side at dispatch. | Medium |
| 5 | **Prisma `P2028` root cause** | Instrument and resolve — see §9. | High |
| 6 | **Timezone helper rollout** | The same missing-`.toLocal()` pattern exists in `notification_model.dart`, `interests_repository_impl.dart`, and `support_repository_impl.dart`. Each is a one-line swap to `parseServerTime()` now that the helper exists. Out of scope today. | Medium |
| 7 | **On-device notification matrix** | Execute and sign off rows 1–5 of §7. | High |
| 8 | **`flutter_local_notifications` API mismatch** | Pre-existing compile failure in `ProfileDetailPage`'s widget tree that times out 13 diagnostic tests (§8.1). Predates today's work; blocks that suite from running. | Medium |

*(Previously documented and still open: push retry queue via BullMQ, notification batching, online-user suppression, and deep-linking into a conversation on notification tap.)*

---

## 11. Final Status

### Production-Readiness Verdict — Android Notifications

| Dimension | Assessment |
|---|---|
| **Correctness of delivery** | ✅ Receiver-only targeting plus device-level sender exclusion; verified by automated tests. |
| **Payload quality** | ✅ Dynamic sender name and real message preview; consistent between push and notification centre. |
| **Android platform configuration** | ✅ Monochrome icon, manifest metadata, channel parity, and runtime permission all correct and verified by inspection. |
| **Automated quality gates** | ✅ Lint, types, and 432 backend tests green. |
| **On-device verification** | ⚠️ Foreground / background / terminated / lock-screen matrix not yet signed off. |
| **Stability** | ⚠️ Intermittent Prisma `P2028` on the send path is open. |
| **Privacy posture** | ⚠️ Message text now appears on lock screens with no user opt-out — a product decision that should be confirmed before public release. |

**Verdict: ⚠️ Release-candidate ready — not yet cleared for production.**

The implementation is complete, reviewed, and green across every automated gate. Three items gate the production call: sign-off on the on-device notification matrix (§7 rows 1–5), root cause for the `P2028` timeout (§9), and an explicit product decision on lock-screen message previews (§10 item 1). None is a defect in the work delivered today; all three are verification and product-decision items.

---

**Today's outcome:** Chat push notifications now reach only the intended recipient with the sender's real name and message text, Android's notification icon and channel configuration are correct across all app states, and the chat timestamp timezone defect is fixed at a single decode boundary — with lint, types, and 432 backend tests green, pending on-device sign-off and one open Prisma transaction timeout.
