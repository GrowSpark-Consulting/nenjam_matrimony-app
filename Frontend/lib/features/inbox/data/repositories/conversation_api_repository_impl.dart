import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../discover/data/models/discovery_profile_model.dart';
import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/conversation_repository.dart';

/// Real backend implementation — dormant, not wired to any provider.
///
/// TODO(backend): `ApiEndpoints.conversations`/`.messages` are proposed
/// paths — the `chat` controller doesn't exist yet. Proposed shapes:
///  - `GET {conversations}?page&limit` -> `{ items: [...], page, limit,
///    total, hasMore }`, each item `{ id, profile: DiscoveryProfileDto,
///    lastMessage, lastMessageAt, unreadCount, isTyping, isPinned, isMuted,
///    isArchived, isBlocked, isLocked, lastMessageFromMe, lastMessageStatus,
///    smartIndicator }`.
///  - `GET {messages}?conversationId&page&limit` -> bare JSON array of
///    `{ id, conversationId, text, sentAt, isMine, status, type }`.
///  - `POST {messages}` with `{ conversationId, text }` -> created message.
///  - `PATCH {conversations}/:id` with `{ pinned | muted | archived |
///    blocked }` for the corresponding toggle actions; `DELETE
///    {conversations}/:id`; `POST {conversations}/:id/read` /
///    `.../unread`.
///
/// Swap `conversationRepositoryProvider` (inbox_providers.dart) from
/// [ConversationRepositoryImpl] to this class once that controller ships —
/// nothing else in the feature needs to change.
class ConversationApiRepositoryImpl implements ConversationRepository {
  ConversationApiRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

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
  Future<List<MessageEntity>> getMessages(String conversationId, {int page = 1, int limit = 30}) async {
    final response = await _apiClient.get<List<dynamic>>(
      ApiEndpoints.messages,
      queryParameters: {'conversationId': conversationId, 'page': page, 'limit': limit},
    );
    final data = unwrapOrThrow(response.statusCode, response.data);
    return (data ?? []).cast<Map<String, dynamic>>().map(_messageFromJson).toList();
  }

  @override
  Future<MessageEntity> sendMessage(String conversationId, String text) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.messages,
      data: {'conversationId': conversationId, 'text': text},
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    return _messageFromJson(data);
  }

  @override
  Future<void> pin(String conversationId, bool pinned) => _patch(conversationId, {'pinned': pinned});

  @override
  Future<void> mute(String conversationId, bool muted) => _patch(conversationId, {'muted': muted});

  @override
  Future<void> archive(String conversationId, bool archived) => _patch(conversationId, {'archived': archived});

  @override
  Future<void> block(String conversationId, bool blocked) => _patch(conversationId, {'blocked': blocked});

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

  MessageEntity _messageFromJson(Map<String, dynamic> json) => MessageEntity(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        text: json['text'] as String? ?? '',
        sentAt: DateTime.parse(json['sentAt'] as String),
        isMine: json['isMine'] as bool? ?? false,
        status: MessageStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => MessageStatus.sent,
        ),
        type: MessageType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => MessageType.text,
        ),
      );
}
