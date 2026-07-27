# Chat/Messaging Backend Handoff

Scope: the Inbox "Messages" tab and Chat Detail thread — everything the frontend now
expects from a real chat backend, and exactly what's mocked/local vs. genuinely
connected today. Companion to `backend-handoff-2026-07-25.md` (which flagged chat as
priority #2, right after Interests+Notifications+Shortlist); this note goes into the
detail that one only summarized.

The frontend feature is **fully built and usable right now against a mock repository**.
Nothing below is a blocker for using/demoing the app — it's a spec for wiring the real
thing in behind the same interface.

**Status, precisely** (do not read anything below as "chat backend connected" — it isn't):

| | |
|---|---|
| Frontend (UI, state, optimistic send/retry, pagination, scroll behavior) | ✅ FRONTEND FUNCTIONAL |
| Mock repository (`ConversationRepositoryImpl`) | ✅ MOCK DATA FUNCTIONAL |
| REST adapter (`ConversationApiRepositoryImpl`) | ✅ REST ADAPTER READY (written, mapped to the real schema, **not wired to any provider**) |
| Database schema (`ChatRoom`/`ChatMessage`/`MessageReaction`/`UserBlock`) | ✅ PRISMA CHAT SCHEMA EXISTS (migrated, unused) |
| REST endpoints (`ConversationsController`/`MessagesController`/services/repositories) | ❌ REAL CHAT REST BACKEND NOT IMPLEMENTED (empty stub classes, `ChatModule` not registered in `app.module.ts`) |
| Socket events (`ChatGateway`) | ❌ REAL CHAT SOCKET EVENTS NOT IMPLEMENTED (empty stub class, no event contract defined) |

---

## 1. What was inspected before writing this

Every backend chat-related file was read directly, not assumed:

- `backend/apps/api/src/modules/chat/` — `chat.module.ts`, both controllers
  (`ConversationsController`, `MessagesController`), both repositories, both services,
  both DTOs (`ConversationResponseDto`, `MessageResponseDto`), both entities, the
  `ChatEventsEmitter`, the `ConversationParticipantGuard`, and `messages.service.spec.ts`.
  **Every one of these is a literal empty stub class** (e.g. `export class
  MessagesController {}`) — no routes, no DTO fields, no logic, no tests beyond an
  `it.todo(...)`. `ChatModule` is also **not imported into `app.module.ts`**, so even if
  the controllers had bodies, nothing would be routable yet.
- `backend/apps/websocket/src/gateways/chat.gateway.ts` — `// TODO: implement with
  @nestjs/websockets + socket.io once those packages are installed. export class
  ChatGateway {}`. Also a stub; `apps/websocket` is a separate NestJS app from `apps/api`
  (see §5).
- `backend/libs/database/prisma/schema.prisma` — **this part is real and already
  migrated**: `ChatRoom`, `ChatMessage`, `MessageReaction`, and `UserBlock` models all
  exist with concrete fields (quoted in full below). This is the one source of truth this
  handoff is grounded in — everything else below is either a direct read of that schema
  or an explicitly-labeled proposal.

**IMPLEMENTED FRONTEND** below means: built, working today against the mock repository,
and already shaped to call a real backend without any UI/state-management rewrite.
**BACKEND REQUIRED** means: no working backend exists for it yet — every item in that
category traces back to one of the empty stub files above.

---

## 2. The real Prisma schema (already migrated — this is not a proposal)

```prisma
model ChatRoom {
  id            String    @id @default(uuid())
  user1Id       String
  user2Id       String
  isActive      Boolean   @default(true)
  lastMessageAt DateTime?
  createdAt     DateTime  @default(now())
  updatedAt     DateTime  @updatedAt
  @@unique([user1Id, user2Id])
}

model ChatMessage {
  id        String      @id @default(uuid())
  roomId    String
  senderId  String
  content   String
  type      MessageType @default(TEXT)   // TEXT | IMAGE | AUDIO | VIDEO
  mediaUrl  String?
  isRead    Boolean     @default(false)
  readAt    DateTime?
  deletedAt DateTime?
  createdAt DateTime    @default(now())
}

model MessageReaction {
  id        String   @id @default(uuid())
  messageId String
  userId    String
  emoji     String
  createdAt DateTime @default(now())
  @@unique([messageId, userId])
}

model UserBlock {
  id            String   @id @default(uuid())
  blockerId     String
  blockedUserId String
  createdAt     DateTime @default(now())
}
```

Four things this implies that the frontend's own model **doesn't** currently have a
1:1 match for — worth resolving before implementation starts, not after:

1. **No "delivered" status.** `ChatMessage` only has `isRead`/`readAt` — no separate
   delivery-acknowledgement column. The frontend's `MessageStatus.delivered` (a full
   sending → sent → delivered → read progression) has nothing to map from until the
   backend adds one. Until then, a real integration can only ever produce `sent` or
   `read`, never `delivered`.
2. **`isBlocked` is not a `ChatRoom` field.** Blocking is a separate `UserBlock` table
   (`blockerId`/`blockedUserId`), not a per-conversation flag. A conversation's
   "blocked" state is really "is `UserBlock` where `blockerId = me` and
   `blockedUserId = the other participant`" — a join, not a toggle on the room.
3. **No columns at all for** `isPinned`, `isMuted`, `isArchived`, `isLocked`,
   `isTyping`, `smartIndicator`, or a cached `lastMessage`/`lastMessageStatus` on
   `ChatRoom`. Every one of these is currently a frontend-only concept
   (`ConversationEntity`) with nothing to persist to. Pin/mute/archive need either new
   `ChatRoom` columns or a separate per-user-per-room preferences table; `isLocked`
   (premium gating) and `smartIndicator` (new match / interest accepted / etc.) are
   presumably derived from other tables (`UserSubscription`, `ExpressInterest`) rather
   than stored directly — not designed here, flagging that the design question is open.
4. **`MessageType` has no `DOCUMENT` value** (`TEXT | IMAGE | AUDIO | VIDEO`). The
   frontend's `MessageType.document` has no backend equivalent yet; `AUDIO` does cover
   `MessageType.voice`.

`senderId`/`user1Id`/`user2Id` reference the backend's internal user id. **Open
question, not resolved by this note:** confirm whether that's the same value as the
Firebase UID the frontend already uses everywhere else
(`authRepositoryProvider.currentUser?.uid`), or a separate internal id — the API
repository (§4) needs whichever one is correct to compute `isMine` (`senderId ==
currentUserId`).

---

## 3. IMPLEMENTED FRONTEND

All of this exists today, working against the mock repository
(`ConversationRepositoryImpl` / `ConversationMockDataSource`), reachable via
`Frontend/lib/features/inbox/`:

- **Inbox list**: loading/empty/error/loaded states, pull-to-refresh, local search
  (name/matrimony id/last message), filter sheet (unread/online/verified/premium/
  recent/archived/blocked), swipe actions (pin, mark-unread, archive, delete),
  long-press options sheet (view profile, mute, archive, block, delete), unread badge
  on the Messages tab.
- **Chat Detail thread**: date-separated message list, left/right bubble alignment,
  per-message status ticks (sending/sent/delivered/read/failed rendered from
  `MessageStatus`), typing indicator UI (driven by `ConversationEntity.isTyping`, a
  static mock field today — see §6), locked-conversation premium upsell screen,
  blocked-conversation banner with unblock action.
- **Send, with optimistic UI and reconciliation by `clientMessageId`** (not list
  position) — a message appears instantly as `sending`, resolves to the server's
  version on success, or flips to `failed` with a tap-to-retry affordance on failure.
  `MessagesNotifier.retry(clientMessageId)` re-sends in place (same bubble, same
  position) rather than appending a new one. Rapid double-tap on Send is guarded (the
  send button swaps to disabled/mic the instant the field clears).
- **Image attachments**: camera/gallery picker (same UX pattern as
  `PhotoManagerSection`'s profile-photo picker), preview strip with remove-before-send,
  `sending` overlay + spinner on the bubble while "uploading", broken-image fallback.
  Sends through the same optimistic/`clientMessageId` pipeline as text.
- **Pagination**: `MessagesNotifier.loadOlder()` fetches the next-older page when the
  user scrolls near the top, prepends it, and corrects the scroll offset by the exact
  height of the newly-inserted content so the view doesn't visually jump. Backed by a
  real (if currently small — one seeded conversation has 45 messages specifically to
  exercise this) paginated mock, not a fetch-everything shortcut.
- **Smart auto-scroll**: your own sent messages always scroll to bottom; an incoming
  message only auto-scrolls if you were already near the bottom — otherwise a "New
  messages (n)" pill appears and scrolls down on tap. Scrolled-up reading position is
  never yanked out from under you.
- **Read/unread**: opening a conversation marks it locally read (`unreadCount` → 0,
  optimistic + persisted through the repository); the Messages tab badge
  (`unreadConversationsCountProvider`) reflects it immediately.
- **Confirmation dialogs** on Block and Delete (both the Chat Detail app-bar menu and
  every Inbox entry point — swipe action and long-press sheet) — unblocking/unmuting/
  archiving stay one-tap since they're reversible.
- **Chat → Profile Detail** navigation goes through the existing
  `core/router/profile_navigation.dart#openProfileDetail` helper — no second
  navigation path was introduced (the recent GoRouter duplicate-page-key fix is
  untouched by this feature).
- **Profile Detail's "Message" action is now interest-gated**, not a blind redirect to
  the generic Inbox. `interest_button_copy.dart`'s `handleInterestButtonTap`/
  `handleMessageButtonTap` are the single place that decides, keyed off the existing
  `InterestRelationshipStatus` (`none`/`sent`/`received`/`accepted`/`declined`/
  `cancelled` — no new statuses invented):
  - `accepted` → resolve the conversation for that specific profile
    (`ConversationsNotifier.getOrCreateConversationFor`, which prefers an
    already-loaded conversation over a repository round-trip) and push Chat Detail for
    it directly (`openChatDetail` — a plain `context.push` on the ordinary root-level
    `chatDetail` route, not the `messages` shell branch, so it can't reproduce the
    duplicate-Page-key issue that route's `.go()` fix was for).
  - `none`/`cancelled` → snackbar "Send an interest first…" with a **Send Interest**
    action that calls the existing `InterestsNotifier.sendInterest` (no duplicated
    send logic).
  - `sent` → snackbar "Your interest is pending…", no action.
  - `received` → snackbar "Respond to their interest first…" with an action that opens
    Received Interests (existing route), where accept/decline already live.
  - `declined` → snackbar noting it was declined, no action.
  - A resolved conversation that's `isBlocked` shows the blocked-conversation message
    instead of opening chat, and a failed lookup shows "Unable to open chat" and stays
    on Profile Detail — it never navigates on failure.
  - Both the gold pill (relabels to "Message" once accepted) and the small chat-icon
    button share this logic and are each individually guarded against rapid-tap
    (disabled + spinner while resolving), so double-tapping can't open two Chat Detail
    pages.

---

## 4. Repository/model shape the backend needs to satisfy

`Frontend/lib/features/inbox/domain/repositories/conversation_repository.dart` is the
interface; `ConversationApiRepositoryImpl` (same directory, `data/repositories/`,
**dormant — not wired to any provider**) is the REST implementation, already written
against the real Prisma field names above (`content`/`senderId`/`mediaUrl`/`isRead`/
`createdAt`/`roomId` — not the frontend's own `text`/`isMine`/`attachmentUrl`/`status`/
`sentAt`/`conversationId` property names, which it maps to/from). Read that class's doc
comment for the full mapping; summary:

| Method | Proposed endpoint | Notes |
|---|---|---|
| `getConversations` | `GET /chat/conversations?page&limit` | `{ items, page, limit, total, hasMore }` |
| `getOrCreateConversation` | `POST /chat/conversations/get-or-create` | body `{ peerId }` → existing or newly-created `ChatRoom` `{ id, lastMessageAt, lastMessage }`. Backs Profile Detail's "Message" action — see §3. **Must reject unless an ACCEPTED `ExpressInterest` exists between the two users** (either direction) — see the security note below. |
| `getMessages` | `GET /chat/messages?conversationId&page&limit` | `{ items, page, hasMore }` — page 1 = newest slice, increasing page = further into the past |
| `sendMessage` | `POST /chat/messages` | body `{ roomId, content, clientMessageId, type, mediaUrl }` |
| `pin` / `mute` / `archive` | `PATCH /chat/conversations/:id` | body `{ pinned \| muted \| archived }` — needs new columns, see §2.3 |
| `block` | `POST /chat/conversations/:id/block` \| `.../unblock` | proposed as its own endpoint since it's a `UserBlock` row, not a room field |
| `delete` | `DELETE /chat/conversations/:id` | |
| `markRead` / `markUnread` | `POST /chat/conversations/:id/read` \| `.../unread` | |
| `setTyping` | *(not REST — see §6)* | |

**Cutover**: once real, swap `conversationRepositoryProvider`
(`inbox_providers.dart`) from `ConversationRepositoryImpl` to
`ConversationApiRepositoryImpl(ref.watch(apiClientProvider), currentUserId: () =>
<resolved answer to the senderId question in §2>)`. No other frontend file changes.

### `clientMessageId` reconciliation

`MessageEntity.clientMessageId` has **no backing column** on `ChatMessage` and doesn't
need one — the backend only needs to echo it back on the response to `POST
/chat/messages` (or, later, on a socket-pushed message-created event — see §6) so the
client can match its optimistic bubble to the confirmed message. For a synchronous
REST send, the frontend doesn't even strictly need the echo (it already knows which id
it just sent) — the echo starts mattering once message confirmation can arrive
asynchronously over a different channel than the request.

---

## 5. BACKEND REQUIRED

Everything here has zero working implementation today — every referenced file is one
of the empty stubs listed in §1:

1. **`ChatModule` registration** — not imported into `app.module.ts`; nothing below is
   reachable until it is (same situation Interests/Notifications/Shortlist were in
   before their handoff).
2. **`ConversationsController`/`MessagesController`** — implement the endpoints in the
   table above (§4), backed by `ConversationRepository`/`MessageRepository`/
   `ConversationsService`/`MessagesService` (all currently 3-line stubs) and
   `ConversationResponseDto`/`MessageResponseDto` (currently empty classes).
3. **`ConversationParticipantGuard`** — stubbed with a `TODO: implement CanActivate`
   comment; needed so `GET/POST` on a conversation can't be called by someone who isn't
   `user1` or `user2` on that `ChatRoom` row.
4. **Chat-eligibility enforcement — accepted-interest gating, server-side.** The
   frontend now only offers "Message" once `InterestRelationshipStatus.accepted`, but a
   frontend check is not security: nothing stops a direct API call. The backend must,
   independently:
   1. Verify an ACCEPTED `ExpressInterest` exists between user A and user B (either
      direction) before doing anything else.
   2. Only then get/create the `ChatRoom` for that pair (`getOrCreateConversation`,
      §4) — never create one for a non-accepted pair.
   3. Return the room/conversation id to the caller.
   4. Reject `getOrCreateConversation` outright (403, not a silent no-op) if the pair
      isn't accepted — including if an interest was later declined/withdrawn after a
      room already existed, per whatever Nenjam's product rule for that case turns out
      to be (not decided here).
   5. Reject `sendMessage` the same way — a room existing once is not proof the pair is
      still chat-eligible at send time; both `getOrCreateConversation` and every
      `sendMessage` call need this check, not just the former.
5. **New columns or a companion table** for `isPinned`/`isMuted`/`isArchived` (see
   §2.3) — these three are simple per-user toggles the frontend already round-trips
   correctly through `PATCH`, they just need somewhere to persist.
6. **`isLocked`/`smartIndicator` derivation** — design question, not just missing code:
   where do these come from (subscription tier, recent `ExpressInterest` status,
   AI-match scoring)? Not resolved here.
7. **Delivered status** (see §2.1) — either add a column/event for it, or the frontend
   accepts that real conversations will only ever show sent/read, never delivered,
   which is a product decision worth making explicitly rather than by omission.
8. **Attachment upload endpoint** — nothing proposed yet. `ConversationApiRepositoryImpl.
   sendMessage`'s `mediaUrl` assumes the file was already uploaded through a *separate*
   call before the message POST, mirroring the existing pattern
   `PhotoRepository`/`ApiClient.upload()` uses for profile photos — but no endpoint
   exists for chat attachments specifically. Until one does, the mock repository just
   accepts the local file path as-is so the send/preview/failed-state UI can be
   exercised end-to-end (see §7) — this is explicitly not a real upload and must not be
   mistaken for one.
9. **Realtime chat events** (§6) — the entire `ChatGateway` implementation.

---

## 6. Realtime readiness

`core/realtime/RealtimeService` (`Frontend/lib/core/realtime/`) is a **shared,
already-working** Socket.IO client — connection/auth/reconnect all proven today for
three unrelated event types (`interestCreated`, `interestAccepted`, `interestRejected`
— plus `notificationCreated`, `shortlistCreated`). Chat should use this **same
connection**, not a second one.

**Deliberately not done yet**: no chat event names were added to `RealtimeEvent`
(`core/realtime/realtime_event.dart`), and `ChatComposer`'s typing callback
(`onTypingChanged`) only calls `ConversationRepository.setTyping()`, which is a
documented no-op in both the mock and API repositories. Per the brief for this work:
hardcoding guessed event names (e.g. `message:new`, `typing:start`) into the shared
enum would be inventing a contract the backend hasn't defined — `chat.gateway.ts` is a
completely empty class, so there is nothing to confirm those names against yet.

What's actually needed once `ChatGateway` exists:
- Real event names for: new message, message read (receipt), typing started/stopped,
  conversation updated (for the two `UserBlock`/pin-mute-archive-adjacent cases that
  don't fit REST's request/response shape).
- A design decision on **payload push vs. refresh signal**: the existing three event
  types are "something changed, go refetch" signals (`realtimeSyncProvider` just calls
  `ref.invalidate(...)` on the matching notifier). Chat likely needs the *actual
  message payload* pushed inline (so a message can appear without a round-trip fetch),
  which is a different, richer pattern than what's there today — worth deciding
  explicitly before implementing, not accreting into the existing switch statement.
- Once both exist: add the event(s) to `RealtimeEvent`, a case in
  `realtimeSyncProvider` that updates `messagesProvider`/`conversationsNotifierProvider`
  instead of only invalidating, and wire `ChatComposer.onTypingChanged` through
  `RealtimeService` instead of the current no-op repository hook.

---

## 7. MOCK/PLACEHOLDER

Explicitly not real, isolated to `ConversationRepositoryImpl`/`ConversationMockDataSource`
(never present in `ConversationApiRepositoryImpl`):

- All conversation/message data — 13 seeded conversations, in-memory, reset on app
  restart.
- **Send failure simulation**: sending the literal text `"fail"` (case-insensitive)
  throws deliberately, so the retry-on-failure UI has a deterministic way to be
  exercised without relying on random flakiness. Real backend errors will surface
  through the same `failed` status path automatically — no frontend change needed
  when that happens for real.
- **Image "upload"**: the mock accepts whatever local file path it's given as if it
  were already a hosted URL (see §5.7) — there is no real upload happening.
- **Typing indicator**: `ConversationEntity.isTyping` is a static field seeded per
  mock conversation (one conversation, `c2`, is seeded `isTyping: true` permanently) —
  it does not react to anything and never turns off. It exists purely so the UI
  (bubble/row rendering) has something to display; it is not a simulation of live
  typing behavior.
- **Pagination depth**: only conversation `c1` has a long (45-message) seeded thread
  specifically so `loadOlder()` has more than one page to fetch during testing; every
  other conversation has the original 5-message thread and will report `hasMore:
  false` immediately.

---

## 8. ALREADY CONNECTED

- **Auth**: every repository call already carries a Firebase ID token automatically
  via `ApiClient`'s `AuthInterceptor` (shared with every other feature) — nothing
  chat-specific to wire here once the endpoints exist.
- **Realtime transport**: connection/reconnect/auth-token-refresh (see §6) — proven,
  reusable, no new socket plumbing needed, only new event handling.

---

## 9. Suggested order for the backend dev

1. Register `ChatModule` in `app.module.ts` and implement `GET/POST` conversations +
   messages (§4, §5.1–5.3) — this alone unblocks the mock→real cutover for the entire
   feature described in §3.
2. Resolve the `senderId`/Firebase-UID question (§2) — blocks `isMine` from ever being
   correct client-side otherwise.
3. Decide + implement `isPinned`/`isMuted`/`isArchived` persistence (§5.4).
4. Decide the delivered-status and `isLocked`/`smartIndicator` design questions (§5.5,
   §5.6) — not urgent for a first cutover (both degrade gracefully: no delivered tick,
   `isLocked`/indicators just don't show), but worth deciding rather than leaving
   implicit.
5. Attachment upload endpoint (§5.7) — blocks image messages specifically; text-only
   chat can ship without it.
6. `ChatGateway` + realtime event contract (§6) — chat is fully usable via polling/
   refresh without this (same as Interests/Notifications/Shortlist today), but won't
   feel "live" until it exists.
