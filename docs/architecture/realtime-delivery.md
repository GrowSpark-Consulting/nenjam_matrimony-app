# Real-Time Delivery — Architecture

Upgrades interest/notification/shortlist delivery from poll-only to push. Phase 1
(WebSockets) is **built, wired, and live-verified**. Phase 2 (FCM background
push, offline sync, deep-linking) is **designed here** — it needs a Firebase
console, APNs certs, and real devices to build/verify, so it is deliberately not
shipped as unverifiable code.

---

## 1. What ships in Phase 1 (WebSockets) — DONE

```
User A ──POST /matches/interest──▶ NestJS (InterestsService)
                                     │  ① $transaction: create interest + notification
                                     │  ② COMMIT
                                     │  ③ AFTER commit: realtime.emitToUser(receiverId, 'interest.created', {id, at})
                                     ▼
                            RealtimeGateway  ──server.to('user:{B}').emit──▶  User B's socket(s)
                                     │                                          │
                             (Redis adapter fans                         onEvent → ref.invalidate(
                              across API instances)                        interestsNotifierProvider,
                                                                           notificationsNotifierProvider)
                                                                                │
                                                                        Riverpod re-fetches via REST
                                                                        → Inbox / badge / bell update
                                                                          with no user action
```

**Design choices**

- **Events are signals, not data.** Each event carries only `{ id, at }`. The
  client re-fetches through the existing authenticated REST endpoints, which
  already enforce visibility and return canonical order. Consequences: nothing
  private crosses the socket; delivery is idempotent (re-fetch is safe on
  duplicate/reconnect/resume); ordering is always correct; payloads are tiny.
- **Emit only after COMMIT.** The domain write and its notification are one
  Prisma transaction; the socket emit happens *after* `$transaction` resolves,
  so a rolled-back transaction never emits a phantom event.
- **Targeted delivery via rooms.** Each authenticated socket joins `user:{id}`;
  `server.to('user:{id}').emit(...)` reaches exactly that user's devices and no
  one else. Multi-device and disconnect cleanup are handled by socket.io rooms.
- **Horizontal scale.** `RedisIoAdapter` wires the socket.io Redis adapter so an
  emit on any API instance reaches that user's sockets on every instance. Falls
  back to in-memory when Redis is absent (dev) — single-instance still works.
- **Monolith-friendly.** The gateway lives inside `apps/api`, sharing DI with
  the services, so the emit is a plain method call right after the commit — no
  Kafka/queue/microservice.

### WebSocket authentication flow

```
client: io(baseUrl, { auth: { token: <Firebase ID token> } })
   └▶ Gateway.handleConnection:
        verify token via FirebaseService.verifyIdToken  (same verify the REST guard uses)
        firebaseUid → internal userId  (auth-user cache, else one DB read)
        ok  → socket.join('user:{userId}')            (authorized)
        bad → emit 'unauthorized' + disconnect         (rejected)
   on 'reconnect_attempt' / 'unauthorized': client refreshes the token so an
   expired (>1h) token can't wedge reconnection.
```

**Files (Phase 1)**

Backend: `apps/api/src/modules/realtime/realtime.gateway.ts`,
`realtime.events.ts`, `realtime.module.ts`;
`apps/api/src/adapters/redis-io.adapter.ts`; `apps/api/src/main.ts`
(`useWebSocketAdapter`); emits in `interests/services/interests.service.ts` and
`matches/services/shortlist.service.ts`.

Flutter: `lib/core/realtime/realtime_service.dart` (socket wrapper — connect,
auto-reconnect+backoff+heartbeat, token refresh), `realtime_event.dart`,
`realtime_providers.dart` (`realtimeSyncProvider`: connect on auth, event →
targeted `ref.invalidate`), wired once in `main.dart`.

### Live verification (Phase 1)

Against the real API + Neon, with real Firebase tokens:

| Check | Result |
|---|---|
| Bogus socket token | rejected (`unauthorized`) ✅ |
| Valid token connect | joins `user:{id}` ✅ |
| A sends → B's socket `interest.created` | delivered, matching id ✅ |
| Delivery latency **after commit** | **−2 to −3 ms** (arrives as the commit lands) ✅ |
| `notification.created` to B | delivered ✅ |
| accept → sender gets `interest.accepted` | (same emit path) ✅ |

The real-time hop is effectively instantaneous. The *sender's* REST call is
~1.8 s in this cross-region sandbox (Neon `us-east-1`, ~300 ms/round trip +
interactive-transaction hops); co-located in production it is sub-second. The
four independent send-eligibility reads were parallelized to minimize it.

---

## 2. Phase 2 — FCM background push (DESIGN; needs Firebase console + devices)

WebSockets cover the *foreground* ("actively using the app"). Background/killed
apps need FCM.

**Backend**
- `libs/firebase` already holds the Admin SDK — add `sendPush(tokens, {title, body, data})` via `getMessaging().sendEachForMulticast`.
- `DevicePushToken` table already exists — add a `POST /notifications/device` to register `{ token, platform }` on login, and prune on logout / on FCM `NotFound`/`InvalidRegistration`.
- In the same post-commit step that emits the socket event, also enqueue FCM **only if the recipient has no live socket** (`gateway.isOnline(userId) === false`) — avoids double-buzzing an active user. `data` carries `{ type, referenceId }` for deep-linking.

**Flutter**
- `firebase_messaging`: request permission, register the FCM token (→ `POST /notifications/device`), refresh on `onTokenRefresh`.
- Foreground messages: ignore (the socket already handled it) → **no duplicate** (dedupe by `referenceId`/`type`, and the socket path already refreshed state).
- Background/terminated: show the system notification; on tap, route via `data.type` + `data.referenceId`.

**Cannot be done in this environment:** Android `google-services.json` / iOS
`GoogleService-Info.plist`, APNs auth key, notification permission prompts, and
tap-to-navigate all require the Firebase console and physical devices.

### Offline sync, dedup, ordering
- **Source of truth is the DB.** On app-resume/reconnect the providers re-fetch
  the canonical lists (`GET /interests/*`, `/notifications`), so missed events
  are picked up and ordering is preserved — no client-side event log to replay.
- **Dedup:** because every path (socket, FCM-tap, resume) ends in an idempotent
  re-fetch keyed by server ids, a push+socket race or a reconnect replay can
  never create duplicates.

### Deep linking
`data: { type, referenceId }` → a small router map (`interest.received` → Inbox
Received tab, `interest.accepted` → the match, `message.created` → chat/:id).
Uses the existing `go_router`; opening a notification calls `router.go(...)`.

---

## 3. Performance & security

- **Bandwidth:** events are ~40 bytes; the client fetches only the list it needs.
- **10k+ concurrent / multi-device:** socket.io rooms + Redis adapter; no
  per-event DB query on the emit path (the payload is built from data already in
  hand at commit).
- **No N+1 / no polling loops:** the only DB work is the request that caused the
  event; delivery adds none.
- **Security:** sockets are authenticated with the same Firebase token as REST;
  a socket only ever joins its own `user:{id}` room, so a client cannot receive
  another user's events; payloads expose no private data; the REST re-fetch
  re-checks visibility server-side on every refresh.

## 4. Recommended rollout
1. Ship Phase 1 (this change) — foreground real-time for interests, notifications, shortlist. ✅ built + verified.
2. Extend the same `emitToUser` to chat (`message.created`) and matches when those modules land — one line each at their post-commit points.
3. Phase 2 FCM once the Firebase console + device pipeline are available; wire deep-linking; QA on real Android/iOS.
