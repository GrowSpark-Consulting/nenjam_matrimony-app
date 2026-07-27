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
} as const;

export type RealtimeEvent =
  (typeof RealtimeEvents)[keyof typeof RealtimeEvents];

/** The one payload shape every event carries. `id` identifies the affected
 *  record (for optional optimistic use + client-side dedup); `at` is the server
 *  commit time (ISO) so the client can order/dedupe if it wants. */
export interface RealtimePayload {
  id: string;
  at: string;
}
