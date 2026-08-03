import type {
  MessageDeliveryStatus,
  MessageType,
} from '../../../../../../libs/database/generated/client';

/** Lowercase wire values matching Flutter's MessageDeliveryStatus/MessageStatus
 *  names (`sent`/`delivered`/`read`). */
export type MessageStatusWire = 'sent' | 'delivered' | 'read';

const STATUS_TO_WIRE: Record<MessageDeliveryStatus, MessageStatusWire> = {
  SENT: 'sent',
  DELIVERED: 'delivered',
  READ: 'read',
};

export function deliveryStatusToWire(
  status: MessageDeliveryStatus,
): MessageStatusWire {
  return STATUS_TO_WIRE[status];
}

/**
 * A slim snapshot of the message a [MessageDto] replies to — enough for the
 * client to render a reply-quote (sender/preview/thumbnail/deleted-or-edited
 * state) without a second fetch. Always the message's CURRENT state (this is
 * a live join, not a snapshot frozen at reply time) — if the original is
 * later edited or deleted, the next time this message's DTO is built (a
 * fresh list fetch, a reconnect replay) the quote reflects that update.
 * `isMine`/`mediaUrl` are computed the same way as the top-level [MessageDto]
 * fields they mirror.
 */
export interface MessageReplyDto {
  id: string;
  isMine: boolean;
  type: MessageType;
  content: string;
  mediaUrl: string | null;
  isDeleted: boolean;
  editedAt: string | null;
}

/**
 * One chat message on the wire. Field names match what Flutter's
 * ConversationApiRepositoryImpl._messageFromJson reads (`roomId`, `content`,
 * `mediaUrl`, `isRead`, `createdAt`, `senderId`). `isMine` is computed
 * server-side (from the authenticated user) so the client never needs to know
 * its own internal id; `mediaUrl` is a short-lived presigned URL, never a
 * permanent public link. `clientMessageId` is echoed back only when the caller
 * supplied it, so an optimistic bubble can be reconciled.
 */
export interface MessageDto {
  id: string;
  roomId: string;
  senderId: string;
  isMine: boolean;
  content: string;
  type: MessageType;
  mediaUrl: string | null;
  isRead: boolean;
  status: MessageStatusWire;
  createdAt: string;
  editedAt: string | null;
  replyTo: MessageReplyDto | null;
  clientMessageId?: string;
}

/** Response for `GET /chat/messages/:id/media-url` — a freshly presigned
 *  media URL for a message whose previous one the client detected as
 *  expired (a 403 loading it). `null` if the message has no media, or if
 *  presigning failed (e.g. S3 isn't configured) — a best-effort refresh,
 *  never a hard error for either case. */
export interface MediaUrlRefreshDto {
  mediaUrl: string | null;
}

/** Paginated messages — page 1 is the newest slice, higher pages go further
 *  into the past (matching the client's `loadOlder()`). `nextCursor` is set only
 *  in keyset mode (the caller passed `?cursor=`): pass it back as the next
 *  `cursor` to load the page immediately older, or null when the history ends.
 *  In legacy offset mode it is null and the client keeps using `page`. */
export interface MessagePageDto {
  items: MessageDto[];
  page: number;
  limit: number;
  total: number;
  hasMore: boolean;
  nextCursor: string | null;
}
