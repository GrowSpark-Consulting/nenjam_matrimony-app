import 'package:dio/dio.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/realtime/realtime_event.dart';
import '../../../../core/realtime/realtime_service.dart';
import '../../../discover/data/models/discovery_profile_model.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../mappers/message_wire_mapper.dart';

/// Live backend implementation — wired via `conversationRepositoryProvider`
/// (inbox_providers.dart). Talks to the real `chat` controllers under
/// `backend/apps/api/src/modules/chat/` and the Socket.IO gateway.
///
/// Field mapping to the backend wire shapes:
///  - Conversation (`ChatRoom` + per-user `ChatParticipantState`): `id,
///    profile, lastMessage, lastMessageAt, unreadCount, isTyping, isPinned,
///    isMuted, isArchived, isBlocked, isLocked, lastMessageFromMe,
///    lastMessageStatus, smartIndicator` — see [_conversationFromJson].
///    Blocking is a separate `UserBlock` relation, so it's a dedicated
///    block/unblock endpoint, not the pin/mute/archive PATCH.
///  - Message (`ChatMessage`): wire names differ from [MessageEntity]'s —
///    `content` (not `text`), `mediaUrl` (not `attachmentUrl`), `createdAt`
///    (not `sentAt`). `isMine` and `status` (sent/delivered/read) are computed
///    server-side per viewer and read straight off the payload — the client
///    never needs to know its own internal id. `editedAt` marks an edited
///    message; `clientMessageId` is echoed back so an optimistic bubble
///    reconciles. See [_messageFromJson].
///  - `MessageType` (backend enum): `TEXT, IMAGE, AUDIO, VIDEO`. `AUDIO`
///    covers this app's `voice`; `document` has no backend equivalent.
///
/// Typing and reconnect-replay ride the shared [RealtimeService] socket rather
/// than REST (a per-keystroke POST doesn't fit); incoming message/read/
/// delivered/edit/delete pushes are applied by `chat_realtime_sync.dart`.
class ConversationApiRepositoryImpl implements ConversationRepository {
  ConversationApiRepositoryImpl(this._apiClient, {required this.realtime});

  final ApiClient _apiClient;

  /// The shared socket, used to emit this client's typing state (see
  /// [setTyping]). Inbound events are handled in `chat_realtime_sync.dart`.
  final RealtimeService realtime;

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
      isOnline: data['isOnline'] as bool? ?? false,
      lastSeen: _parseLastSeen(data['lastSeenAt']),
    );
  }

  /// Parses the backend `lastSeenAt` (ISO-8601 string or null) into local time.
  DateTime? _parseLastSeen(dynamic value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  @override
  Future<MessagePage> getMessages(
    String conversationId, {
    int page = 1,
    int limit = 30,
    String? cursor,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.messages,
      queryParameters: {
        'conversationId': conversationId,
        'page': page,
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
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
      nextCursor: data['nextCursor'] as String?,
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
        'type': messageTypeToWire(type),
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
    // Relayed over the socket (throttled server-side) to the room's other
    // participant — never a REST call. No-op when the socket is down; typing is
    // ephemeral and there's nothing to reconcile.
    realtime.emit(
      ChatClientEvent.typing,
      {'roomId': conversationId, 'isTyping': isTyping},
    );
  }

  @override
  Future<MessageEntity> editMessage(String messageId, String content) async {
    final response = await _apiClient.patch<Map<String, dynamic>>(
      '${ApiEndpoints.messages}/$messageId',
      data: {'content': content},
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    return _messageFromJson(data);
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    final response = await _apiClient.delete<Map<String, dynamic>>(
      '${ApiEndpoints.messages}/$messageId',
    );
    unwrapOrThrow(response.statusCode, response.data);
  }

  @override
  Future<String> uploadVoiceAttachment(String localFilePath) async {
    // The `record` package writes AAC-LC in an MP4 container (.m4a) — the
    // Content-Type MUST be set explicitly: Dio's MultipartFile.fromFile
    // defaults to application/octet-stream when it's omitted, which the
    // backend's audio MIME allow-list rejects outright.
    final response = await _apiClient.upload<Map<String, dynamic>>(
      ApiEndpoints.chatAttachmentUpload,
      data: FormData.fromMap({
        'file': await MultipartFile.fromFile(
          localFilePath,
          contentType: DioMediaType('audio', 'mp4'),
        ),
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
  Future<String> uploadImageAttachment(String localFilePath) async {
    final response = await _apiClient.upload<Map<String, dynamic>>(
      ApiEndpoints.chatAttachmentUpload,
      data: FormData.fromMap({
        'file': await MultipartFile.fromFile(
          localFilePath,
          contentType: DioMediaType('image', _imageSubtype(localFilePath)),
        ),
        'type': 'IMAGE',
      }),
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    final mediaUrl = data['mediaUrl'] as String?;
    if (mediaUrl == null) {
      throw const MediaUploadUnavailableException(
        'Image upload is not available yet.',
      );
    }
    return mediaUrl;
  }

  /// Backend's image allow-list is `image/jpeg|png|webp|heic` — mirrors the
  /// extension-to-subtype mapping already used for profile photo uploads.
  String _imageSubtype(String filePath) {
    final dot = filePath.lastIndexOf('.');
    final ext = dot >= 0 ? filePath.substring(dot).toLowerCase() : '';
    return switch (ext) {
      '.png' => 'png',
      '.webp' => 'webp',
      '.heic' || '.heif' => 'heic',
      _ => 'jpeg',
    };
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
        isOnline: json['isOnline'] as bool? ?? false,
        lastSeen: _parseLastSeen(json['lastSeenAt']),
      );

  MessageEntity _messageFromJson(Map<String, dynamic> json, {String? clientMessageId}) =>
      messageEntityFromWire(json, clientMessageId: clientMessageId);
}
