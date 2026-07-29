import type { DiscoverProfileDto } from '../../matches/dto/discover-profile.response.dto';
import type { MessageStatusWire } from './message.response.dto';

/**
 * One conversation row for the Inbox list. Field names match Flutter's
 * ConversationApiRepositoryImpl._conversationFromJson. The fields backed by the
 * current schema are real (`profile`, `lastMessage`, `lastMessageAt`,
 * `unreadCount`, `lastMessageFromMe`, `isBlocked`, `lastMessageStatus`); the
 * per-user room-state fields (`isPinned`/`isMuted`/`isArchived`) and derived
 * fields (`isTyping`/`isLocked`/`smartIndicator`) are sent as safe defaults —
 * they need a per-user-room-state table / product decision (see chat follow-ups)
 * and the client already renders them from these defaults.
 */
export interface ConversationDto {
  id: string;
  profile: DiscoverProfileDto;
  lastMessage: string;
  lastMessageAt: string;
  unreadCount: number;
  lastMessageFromMe: boolean;
  isBlocked: boolean;
  lastMessageStatus: MessageStatusWire | null;
  isPinned: boolean;
  isMuted: boolean;
  isArchived: boolean;
  isTyping: boolean;
  isLocked: boolean;
  smartIndicator: 'none';
}

export interface ConversationPageDto {
  items: ConversationDto[];
  page: number;
  limit: number;
  total: number;
  hasMore: boolean;
}

/** POST /chat/conversations/get-or-create response — just what Profile Detail's
 *  "Message" action needs to open the thread. */
export interface GetOrCreateConversationResponseDto {
  id: string;
  lastMessage: string;
  lastMessageAt: string;
}
