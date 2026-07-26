import type { NotificationType } from '../../../../../../libs/database/generated/client';

/** The person a notification is about (interest sender, shortlister, …), or
 *  null for actor-less notices (system, verification, subscription). */
export interface NotificationActorDto {
  id: string;
  name: string;
  photoUrl: string | null;
}

/**
 * One notification item. Field-for-field the shape Flutter's
 * NotificationModel.fromJson expects. `type` is the raw backend enum string
 * (e.g. "INTEREST_RECEIVED") — the client maps unknown values to a generic
 * category, so adding a new NotificationType never breaks this contract.
 */
export interface NotificationItemDto {
  id: string;
  type: NotificationType;
  title: string;
  message: string;
  isRead: boolean;
  createdAt: string;
  actor: NotificationActorDto | null;
  referenceId: string | null;
  metadata: Record<string, unknown>;
}

/** Paginated envelope for GET /notifications — `hasMore` drives the client's
 *  infinite scroll without it tracking totals itself. */
export interface NotificationsPageDto {
  items: NotificationItemDto[];
  page: number;
  limit: number;
  total: number;
  hasMore: boolean;
}

/** GET /notifications/unread-count. */
export interface UnreadCountDto {
  count: number;
}
