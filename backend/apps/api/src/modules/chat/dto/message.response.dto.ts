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
  clientMessageId?: string;
}

/** Paginated messages — page 1 is the newest slice, higher pages go further
 *  into the past (matching the client's `loadOlder()`). */
export interface MessagePageDto {
  items: MessageDto[];
  page: number;
  limit: number;
  total: number;
  hasMore: boolean;
}
