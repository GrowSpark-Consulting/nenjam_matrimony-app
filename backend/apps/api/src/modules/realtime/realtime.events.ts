/**
 * Real-time socket event names. Payloads are deliberately MINIMAL — an id and a
 * timestamp, never profile/contact data. The event is a *signal to refresh*:
 * the client re-fetches through the existing authenticated REST endpoints,
 * which already enforce visibility and return canonical ordering. That keeps
 * bandwidth tiny, leaks nothing private over the socket, and makes delivery
 * idempotent (a re-fetch is safe to run any number of times — reconnect,
 * resume, or a duplicate push can't corrupt state).
 */
export const RealtimeEvents = {
  interestCreated: 'interest.created',
  interestAccepted: 'interest.accepted',
  interestRejected: 'interest.rejected',
  notificationCreated: 'notification.created',
  shortlistCreated: 'shortlist.created',
  // Chat. Unlike the refresh signals above, `chat.message` carries the full
  // message payload inline so a chat feels instant (the recipient renders it
  // with no round trip) — safe because it's delivered only to that
  // conversation's authenticated participants' rooms. `chat.read` and
  // `chat.typing` are lightweight receipts.
  chatMessage: 'chat.message',
  chatRead: 'chat.read',
  chatDelivered: 'chat.delivered',
  chatTyping: 'chat.typing',
  // Edit carries the updated message inline (same shape as chat.message) so the
  // bubble re-renders in place; delete carries only { id, roomId, at } so the
  // client can drop/tombstone the bubble.
  chatMessageEdited: 'chat.messageEdited',
  chatMessageDeleted: 'chat.messageDeleted',
  // Presence: a participant this user shares a conversation with came online or
  // went offline. Payload `{ userId, isOnline, lastSeenAt }` — pushed only to
  // that user's conversation peers, never broadcast globally.
  chatPresence: 'chat.presence',
} as const;

export type RealtimeEvent =
  (typeof RealtimeEvents)[keyof typeof RealtimeEvents];

/** The payload the refresh-signal events carry. `id` identifies the affected
 *  record (for optional optimistic use + client-side dedup); `at` is the server
 *  commit time (ISO) so the client can order/dedupe if it wants. */
export interface RealtimePayload {
  id: string;
  at: string;
}

/** socket.io room that fans an event out to every device a user has connected.
 *  Shared by every gateway so the room-naming convention is defined once. */
export const userRoom = (userId: string): string => `user:${userId}`;
