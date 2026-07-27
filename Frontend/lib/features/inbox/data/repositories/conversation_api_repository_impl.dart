import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../discover/data/models/discovery_profile_model.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/conversation_repository.dart';

/// Real backend implementation — dormant, not wired to any provider.
///
/// TODO(backend): `ApiEndpoints.conversations`/`.messages` are proposed
/// paths — every controller/service/repository/gateway file under
/// `backend/apps/api/src/modules/chat/` and
/// `backend/apps/websocket/src/gateways/chat.gateway.ts` is an empty stub
/// class today (verified directly — no DTOs, no endpoints, no Socket.IO
/// event names exist yet). The Prisma schema, however, IS already defined
/// (`backend/libs/database/prisma/schema.prisma`) and this class's field
/// mapping below is written to match it exactly, not guessed:
///
///  - `ChatRoom` (-> "conversation"): `id, user1Id, user2Id, isActive,
///    lastMessageAt`. Pin/mute/archive/isTyping/isLocked/smartIndicator/
///    lastMessageStatus/lastMessage — everything [ConversationEntity] needs
///    beyond that — have NO backing column at all yet. `isBlocked` is NOT a
///    room field either: blocking is modeled as a separate `UserBlock`
///    table (`blockerId`, `blockedUserId`), so a conversation's blocked
///    state is really "is the other participant in my block list", not
///    something this endpoint can toggle directly the way `pin`/`mute` can.
///  - `ChatMessage` (-> [MessageEntity]): `id, roomId, senderId, content,
///    type, mediaUrl, isRead, readAt, deletedAt, createdAt`. Note the wire
///    field names differ from this app's own [MessageEntity] property
///    names — `content` (not `text`), `mediaUrl` (not `attachmentUrl`),
///    `createdAt` (not `sentAt`) — mapped below. There is no `isMine`
///    column; it's derived client-side by comparing `senderId` to the
///    signed-in user's own id (TODO: confirm whether `senderId` is the
///    Firebase UID `authRepositoryProvider.currentUser?.uid` already uses
///    everywhere else, or a separate internal user id — this repo needs
///    that answer before it can compute `isMine` correctly, see
///    [currentUserId]). There is also no `status` enum — only `isRead`/
///    `readAt` — so the backend has no "delivered" concept at all today;
///    `MessageStatus.delivered` has nothing to map from until that's added.
///  - `MessageType` (backend enum): `TEXT, IMAGE, AUDIO, VIDEO` — no
///    `DOCUMENT` value, unlike this app's [MessageType.document]. `AUDIO`
///    covers this app's `voice`.
///  - `clientMessageId` has NO backing column on `ChatMessage` — the
///    backend doesn't need to persist it, only echo it back in a
///    synchronous send response (or a socket payload, later) so the
///    client can match its optimistic bubble; see
///    [MessageEntity.clientMessageId]'s doc comment for why it exists at
///    all. [sendMessage] doesn't depend on the echo — it already knows
///    which id it just sent — but a future socket-pushed "message created"
///    event would.
///
/// Proposed (unconfirmed — nothing above exists as a real endpoint yet)
/// REST shape once a real `chat` controller ships:
///  - `GET {conversations}?page&limit` -> `{ items: [...], page, limit,
///    total, hasMore }`, each item shaped like [_conversationFromJson].
///  - `POST {conversations}/get-or-create` with `{ peerId }` -> existing or
///    newly-created ChatRoom. Backs Profile Detail's "Message" action once
///    an interest is accepted — see [getOrCreateConversation]. MUST verify
///    an accepted `ExpressInterest` exists between the two users server-side
///    before creating anything; the frontend only ever calls this after its
///    own (non-authoritative) check passes.
///  - `GET {messages}?conversationId&page&limit` -> `{ items: [...], page,
///    hasMore }`, page 1 being the newest slice (see [MessagePage]'s doc
///    comment), each item shaped like [_messageFromJson].
///  - `POST {messages}` with `{ roomId, content, clientMessageId, type,
///    mediaUrl }` -> created message, echoing `clientMessageId` back.
///  - `PATCH {conversations}/:id` with `{ pinned | muted | archived }` —
///    NOT `blocked`, see above; `DELETE {conversations}/:id`; `POST
///    {conversations}/:id/read` / `.../unread`.
///  - Typing (`setTyping`) is intentionally NOT a REST call here — a
///    per-keystroke POST doesn't fit; it belongs on
///    `core/realtime/RealtimeService` once the backend's socket contract
///    for chat exists (see docs/development/chat-backend-handoff.md). This
///    method is a documented no-op until that lands.
///  - Attachment upload: no endpoint is proposed here yet — `mediaUrl`
///    above assumes the file was already uploaded through a separate call
///    (the pattern `PhotoRepository`/`ApiClient.upload` already uses for
///    profile photos). See the handoff doc for the open question.
///
/// Swap `conversationRepositoryProvider` (inbox_providers.dart) from
/// [ConversationRepositoryImpl] to this class once that controller ships —
/// nothing else in the feature needs to change.
class ConversationApiRepositoryImpl implements ConversationRepository {
  ConversationApiRepositoryImpl(this._apiClient, {required this.currentUserId});

  final ApiClient _apiClient;

  /// Returns the signed-in user's own id, for deriving `isMine` from a
  /// message's `senderId` — see this class's doc comment for the open
  /// question of exactly which id that needs to be.
  final String Function() currentUserId;

  @override
  Future<ConversationResultPage> getConversations({int page = 1, int limit = 20}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.conversations,
      queryParameters: {'page': page, 'limit': limit},
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    final items = (data['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(_conversationFromJson)
        .toList();
    return ConversationResultPage(
      items: items,
      page: data['page'] as int? ?? page,
      limit: data['limit'] as int? ?? limit,
      total: data['total'] as int? ?? items.length,
      hasMore: data['hasMore'] as bool? ?? false,
    );
  }

  @override
  Future<ConversationEntity> getOrCreateConversation(DiscoveryProfileEntity profile) async {
    // Proposed `POST {conversations}/get-or-create` with `{ peerId }` ->
    // the existing or newly-created ChatRoom `{ id, lastMessageAt, ... }`.
    // CRITICAL (see docs/development/chat-backend-handoff.md and this
    // class's doc comment): this call MUST be rejected server-side unless
    // an ACCEPTED ExpressInterest row exists between the caller and
    // `peerId` — [ConversationRepository.getOrCreateConversation]'s doc
    // comment already says the frontend checks this first, but a frontend
    // check is not enforcement; nothing here re-derives that guarantee.
    final response = await _apiClient.post<Map<String, dynamic>>(
      '${ApiEndpoints.conversations}/get-or-create',
      data: {'peerId': profile.id},
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    // `profile` is supplied by the caller rather than re-parsed from the
    // response — the caller already has the full DiscoveryProfileEntity
    // (that's how it knew who to message), so there's no need for this
    // endpoint to echo it back.
    return ConversationEntity(
      id: data['id'] as String,
      profile: profile,
      lastMessage: data['lastMessage'] as String? ?? '',
      lastMessageAt: DateTime.parse(data['lastMessageAt'] as String),
    );
  }

  @override
  Future<MessagePage> getMessages(String conversationId, {int page = 1, int limit = 30}) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.messages,
      queryParameters: {'conversationId': conversationId, 'page': page, 'limit': limit},
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    final items = (data['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(_messageFromJson)
        .toList();
    return MessagePage(
      items: items,
      page: data['page'] as int? ?? page,
      hasMore: data['hasMore'] as bool? ?? false,
    );
  }

  @override
  Future<MessageEntity> sendMessage(
    String conversationId,
    String text, {
    String? clientMessageId,
    MessageType type = MessageType.text,
    String? attachmentUrl,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.messages,
      data: {
        'roomId': conversationId,
        'content': text,
        if (clientMessageId != null) 'clientMessageId': clientMessageId,
        'type': _messageTypeToBackend(type),
        if (attachmentUrl != null) 'mediaUrl': attachmentUrl,
      },
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    // Attached directly rather than relying on the response echoing it
    // back — for this synchronous request/response send, this client
    // already knows exactly which optimistic bubble it's resolving. See
    // this class's doc comment on why a future socket-pushed confirmation
    // would need the backend to echo it instead.
    return _messageFromJson(data, clientMessageId: clientMessageId);
  }

  @override
  Future<void> setTyping(String conversationId, bool isTyping) async {
    // No-op — see this class's doc comment.
  }

  @override
  Future<String> uploadVoiceAttachment(String localFilePath) async {
    // Real call against the proposed (not-yet-registered — see
    // ApiEndpoints.chatAttachmentUpload's doc comment) endpoint. Nothing
    // here fakes success: until that endpoint exists this fails with a
    // genuine network/HTTP error, which `MessagesNotifier` surfaces as the
    // same truthful `MessageStatus.failed` any other real send failure
    // would.
    final response = await _apiClient.upload<Map<String, dynamic>>(
      ApiEndpoints.chatAttachmentUpload,
      data: FormData.fromMap({
        'file': await MultipartFile.fromFile(localFilePath),
        'type': 'AUDIO',
      }),
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    final mediaUrl = data['mediaUrl'] as String?;
    if (mediaUrl == null) {
      throw const MediaUploadUnavailableException(
        'Voice message upload is not available yet.',
      );
    }
    return mediaUrl;
  }

  @override
  Future<void> pin(String conversationId, bool pinned) => _patch(conversationId, {'pinned': pinned});

  @override
  Future<void> mute(String conversationId, bool muted) => _patch(conversationId, {'muted': muted});

  @override
  Future<void> archive(String conversationId, bool archived) => _patch(conversationId, {'archived': archived});

  @override
  Future<void> block(String conversationId, bool blocked) async {
    // Not a ChatRoom field — see this class's doc comment. Proposed as a
    // dedicated endpoint over the room's counterpart user (matching
    // wherever else in the app `UserBlock` rows are created/removed, if
    // that already exists for Discover/Profile Detail's own block action)
    // rather than the conversations PATCH used for pin/mute/archive.
    final response = await _apiClient.post<Map<String, dynamic>>(
      '${ApiEndpoints.conversations}/$conversationId/${blocked ? 'block' : 'unblock'}',
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<void> delete(String conversationId) async {
    final response = await _apiClient.delete<Map<String, dynamic>>(
      '${ApiEndpoints.conversations}/$conversationId',
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<void> markRead(String conversationId) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '${ApiEndpoints.conversations}/$conversationId/read',
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<void> markUnread(String conversationId) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '${ApiEndpoints.conversations}/$conversationId/unread',
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  Future<void> _patch(String conversationId, Map<String, dynamic> data) async {
    final response = await _apiClient.patch<Map<String, dynamic>>(
      '${ApiEndpoints.conversations}/$conversationId',
      data: data,
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  ConversationEntity _conversationFromJson(Map<String, dynamic> json) => ConversationEntity(
        id: json['id'] as String,
        profile: DiscoveryProfileModel.fromJson(json['profile'] as Map<String, dynamic>),
        lastMessage: json['lastMessage'] as String? ?? '',
        lastMessageAt: DateTime.parse(json['lastMessageAt'] as String),
        unreadCount: json['unreadCount'] as int? ?? 0,
        isTyping: json['isTyping'] as bool? ?? false,
        isPinned: json['isPinned'] as bool? ?? false,
        isMuted: json['isMuted'] as bool? ?? false,
        isArchived: json['isArchived'] as bool? ?? false,
        isBlocked: json['isBlocked'] as bool? ?? false,
        isLocked: json['isLocked'] as bool? ?? false,
        lastMessageFromMe: json['lastMessageFromMe'] as bool? ?? false,
        lastMessageStatus: json['lastMessageStatus'] == null
            ? null
            : MessageDeliveryStatus.values.firstWhere(
                (s) => s.name == json['lastMessageStatus'],
                orElse: () => MessageDeliveryStatus.sent,
              ),
        smartIndicator: ConversationSmartIndicator.values.firstWhere(
          (s) => s.name == json['smartIndicator'],
          orElse: () => ConversationSmartIndicator.none,
        ),
      );

  MessageEntity _messageFromJson(Map<String, dynamic> json, {String? clientMessageId}) => MessageEntity(
        id: json['id'] as String,
        conversationId: json['roomId'] as String,
        text: json['content'] as String? ?? '',
        sentAt: DateTime.parse(json['createdAt'] as String),
        isMine: json['senderId'] == currentUserId(),
        // The backend has no "delivered" state (see this class's doc
        // comment) — only isRead/readAt — so this can only ever resolve to
        // sent or read, never delivered, until that's added server-side.
        status: (json['isRead'] as bool? ?? false) ? MessageStatus.read : MessageStatus.sent,
        type: _messageTypeFromBackend(json['type'] as String?),
        attachmentUrl: json['mediaUrl'] as String?,
        clientMessageId: clientMessageId ?? json['clientMessageId'] as String?,
      );

  String _messageTypeToBackend(MessageType type) => switch (type) {
        MessageType.text => 'TEXT',
        MessageType.image => 'IMAGE',
        MessageType.voice => 'AUDIO',
        // No backend equivalent yet — see this class's doc comment.
        MessageType.document => 'TEXT',
      };

  MessageType _messageTypeFromBackend(String? backendType) => switch (backendType) {
        'IMAGE' => MessageType.image,
        'AUDIO' => MessageType.voice,
        'VIDEO' => MessageType.image,
        _ => MessageType.text,
      };
}
