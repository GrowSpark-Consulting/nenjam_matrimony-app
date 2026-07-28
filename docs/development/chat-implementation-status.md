# Chat — Implementation Status & Handoff

_Last updated: 2026-07-28_

End-to-end chat is **built, merged to `main`, and live-verified against the real
database.** This doc is the single hand-off: what shipped, where it lives, how to
run and verify it, and what's intentionally left for later.

Both halves are on `main`:

| PR | Scope | Status |
|----|-------|--------|
| #16 `feat/chat-backend` | Production chat backend (NestJS/Prisma/Socket.IO) | Merged |
| #15 `feat/chat-frontend-cutover` | Flutter cutover from mock → real backend + realtime | Merged |

---

## 1. What chat does now

- **Conversations** — 1:1 rooms, created/opened only when an **ACCEPTED
  `ExpressInterest`** exists between the two users (enforced server-side on
  get-or-create *and* on every send — a room existing once is not proof it's
  still eligible).
- **Messages** — text / image / voice (audio). Idempotent sends
  (`clientMessageId`), delivery states **SENT → DELIVERED → READ**, read
  receipts, typing indicators.
- **Realtime** — Socket.IO. New messages arrive inline (no refetch); read/
  delivered/typing receipts, edit/delete broadcasts, and a reconnect replay for
  anything missed while offline.
- **Per-user conversation state** — pin / mute / archive / mark-unread /
  delete-for-me, each per-user (never on the shared room).
- **Presence** — cross-instance (Redis), drives the SENT-vs-DELIVERED decision;
  multi-device; last-seen.
- **Edit & delete messages** — sender-only; text-only edit within a 15-minute
  window; delete-for-everyone (soft delete). Both broadcast live.
- **Attachments** — uploaded to S3, stored as object keys, returned as
  short-lived **presigned** URLs per read (never permanent public links).
- **Audit trail** — every chat action + authorization denial written to the
  existing `audit_logs` table.

---

## 2. Backend

NestJS monolith (`backend/apps/api`), Prisma 7 + `@prisma/adapter-pg`, Neon
Postgres, Redis (soft dependency), AWS S3, Firebase-JWT auth. All chat code is
under `backend/apps/api/src/modules/chat/` (+ the shared realtime gateway in
`.../modules/realtime/`).

**Architecture:** controller → service → repository → Prisma. Every endpoint
derives the user from the verified Firebase token — **never** from the request
body.

### REST API

All routes are under `FirebaseAuthGuard`; `:id` routes additionally verify the
caller is a participant.

| Method & path | Purpose |
|---|---|
| `GET /chat/conversations?page&limit` | The caller's conversations (last message, unread, peer profile, pin/mute/archive/blocked, typing, last-message status). |
| `POST /chat/conversations/get-or-create` `{ peerId }` | Open/create the thread. **403** unless an ACCEPTED interest exists. |
| `PATCH /chat/conversations/:id` `{ pinned? muted? archived? }` | Per-user flags (partial). |
| `POST /chat/conversations/:id/read` · `/unread` | Mark read / flag unread. |
| `POST /chat/conversations/:id/block` · `/unblock` | Block/unblock the other participant. |
| `DELETE /chat/conversations/:id` | Delete-for-me (hidden until a newer message arrives). |
| `GET /chat/messages?conversationId&page&limit` | Message history, newest first. Optional `cursor=` for keyset pagination (stable under concurrent inserts); `nextCursor` in the response. Backward-compatible with `page`. |
| `POST /chat/messages` `{ roomId, content, clientMessageId?, type?, mediaUrl? }` | Send. Echoes `clientMessageId`. Idempotent. |
| `PATCH /chat/messages/:id` `{ content }` | Edit (sender-only, text-only, 15-min window). |
| `DELETE /chat/messages/:id` | Delete for everyone (soft delete). |
| `POST /chat/attachments` (multipart `file` + `type: IMAGE\|AUDIO`) | Upload → `{ mediaUrl }` (S3 object key). |

### Socket.IO events

Handshake auth is the same Firebase ID token (`auth.token`); each user joins a
per-user room `user:{id}`. With the Redis adapter the same emit fans out across
API instances.

**Server → client** (chat payloads carry the full object inline; only sent to
the conversation's participants):

| Event | Payload |
|---|---|
| `ready` | (none) — socket is authenticated & joined; client should emit `chat.sync` and start its heartbeat now. |
| `chat.message` | full message (per-viewer `isMine`). |
| `chat.messageEdited` | full updated message. |
| `chat.messageDeleted` | `{ id, roomId, at }`. |
| `chat.read` | `{ id: roomId, at }` — the peer read your messages. |
| `chat.delivered` | `{ id, roomId, at }` — your message was delivered. |
| `chat.typing` | `{ roomId, isTyping }`. |
| `presence.pong` | `{ at }` — heartbeat ack. |

**Client → server:** `chat.sync` (reconnect replay), `chat.typing`
`{ roomId, isTyping }`, `presence.ping` (heartbeat, ~25s).

### Schema & migrations

Migrations are hand-written and applied with `prisma migrate deploy` (NOT
`migrate dev` — that hangs on Neon's shadow DB). Both applied to the shared Neon
DB and drift-checked:

- `20260727120000_chat_message_delivery_idempotency` — `MessageDeliveryStatus`
  enum, `ChatMessage.clientMessageId` (unique per sender), `status`,
  `deliveredAt`, `editedAt`.
- `20260727130000_add_chat_participant_state` — new `chat_participant_states`
  table (per-user room state). Additive only.

`ChatRoom`, `ChatMessage`, `MessageReaction`, `UserBlock`, `AuditLog` were
already in the schema.

### Presence (how DELIVERED is decided)

`PresenceService` keeps a per-user Redis **sorted set** (member = socket/device,
score = last-heartbeat epoch-ms). Online = at least one device with a heartbeat
inside the stale window (60s ≈ 2.4× the 25s client heartbeat). Every read/write
prunes stale members, so a device that dropped without a clean disconnect ages
out on its own. When `send()` runs, `presence.isOnline(peer)` decides SENT vs
DELIVERED — correct across instances because the set is in Redis. **Redis is a
soft dependency:** if it isn't up, presence falls back to an in-process mirror
with identical semantics (single-instance correct).

### Security model (do not regress)

- Every endpoint's user comes from the verified Firebase token, never the body.
- Chat requires an ACCEPTED interest — re-checked on get-or-create **and** every
  send; blocking (either direction) also blocks sending.
- Participant-only access on every `:id` route.
- Media stored as S3 keys, presigned per read — never permanent public URLs.
- `backend/.env.local` holds real secrets (Firebase private key, Neon
  `DATABASE_URL`, AWS keys). It is gitignored — **never commit it.**

### Verification (all green)

- `nest build api` clean, eslint clean.
- Unit tests: chat services + presence — **39/39** (`npx jest apps/api/src/modules/chat/tests apps/api/src/modules/realtime/tests`).
- Live end-to-end against Neon with real Firebase-authed tokens + `socket.io-client`:
  interest-gating, get/create, send + realtime, idempotency, delivery states,
  reconnect replay, **per-user state 20/20**, **cursor pagination 11/11**,
  **presence 8/8**, **edit/delete 16/16**, **audit 8/8**.

---

## 3. Frontend (Flutter)

The inbox was cut over from the in-memory mock to the live backend + socket.

- `conversationRepositoryProvider` now builds **`ConversationApiRepositoryImpl`**
  (REST + the shared realtime socket) instead of the mock.
- Messages read server-computed **`isMine`** and **`status`** directly off the
  payload (no client-side guessing). `editedAt` mapped.
- **`editMessage` / `deleteMessage`** added across the repository interface, API
  impl, and mock. `setTyping` emits `chat.typing`. Wire-mapping is centralized
  in `features/inbox/data/mappers/message_wire_mapper.dart`.
- **Realtime** (`core/realtime/realtime_service.dart`): a chat payload stream, an
  outbound `emit`, emits `chat.sync` on `ready`, and a 25s `presence.ping`
  heartbeat.
- **`features/inbox/presentation/providers/chat_realtime_sync.dart`** bridges
  inbound events into inbox state (watched at the app root in `main.dart`).
  Thread updates apply only to *open* threads (`chatActiveThreadsProvider`); the
  conversation list (preview/unread/typing/receipts) updates regardless.
  Incoming messages dedupe by server `id` and reconcile optimistic bubbles by
  `clientMessageId`.
- **UI:** bubbles show an "edited" marker and a "message deleted" tombstone;
  long-press on your own message → edit / delete-for-everyone, optimistic and
  reverted if the server rejects.

`flutter analyze` is clean on all touched code. The test suite is green **except
one pre-existing failure** (`App smoke test` — full-app Firebase init in the test
harness; fails identically on `main` without these changes).

---

## 4. How to run & verify locally

**Backend:**
```bash
cd backend
npx nest build api
node dist/apps/api/main.js        # serves on :3000 (reads .env then .env.local)
```
Redis is optional — the API logs "Redis unavailable — continuing without it" and
uses in-memory fallbacks (presence, socket adapter) when it isn't running.

**Live-test pattern** (how every slice above was verified): mint a Firebase
custom token via `firebase-admin` for a seed user (`%@test10.local`), exchange it
for an ID token via the Identity Toolkit REST endpoint, then call the API with a
Bearer token and connect `socket.io-client` with `{ auth: { token } }`. Insert an
ACCEPTED `ExpressInterest` directly in the DB for the pair, and clean up in a
`finally`. (The throwaway verification scripts were not committed.)

> Note: the sandbox clock is skewed vs Neon's `now()` — filter verification
> queries by `entity_id`, not `created_at >= testStart`, or rows appear missing.

**Frontend:** `flutter analyze` / `flutter test`. Driving a real device needs the
backend deployed (the app calls the real `/chat/*` endpoints and socket).

---

## 5. Pending / follow-ups (nothing blocking)

**Frontend polish**
- New chat UI strings ("Edit", "Delete", "This message was deleted", "edited") are
  literals — localize them (add to the `.arb` files + `gen-l10n`).
- `loadOlder()` still uses offset paging; adopting the backend `cursor` is
  optional (backend already supports it, backward-compatible).
- End-to-end device testing once the backend is deployed.

**Infra-bound (need external services to build/verify — out of scope so far)**
- FCM push notifications for messages received while the app is closed.
- OpenTelemetry / structured observability on the chat hot paths.
- Background workers + DLQ for attachment post-processing (thumbnails, transcode).
- Chaos/load testing of the socket layer under multi-instance + Redis adapter.

**Operational**
- Run the API with **Redis** in staging/prod to get cross-instance presence and
  socket fan-out (single instance works without it).
- Confirm the Redis adapter (`RedisIoAdapter`) is enabled in the deployed config.
