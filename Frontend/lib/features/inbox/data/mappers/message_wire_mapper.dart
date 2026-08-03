import '../../domain/entities/message_entity.dart';

/// Decodes a backend chat-message wire object (`ChatMessage` DTO) into a
/// [MessageEntity]. Shared by [ConversationApiRepositoryImpl] (REST history +
/// send response) and `chat_realtime_sync.dart` (socket `chat.message` /
/// `chat.messageEdited` payloads) so the field mapping lives in exactly one
/// place.
///
/// `isMine` and `status` are computed server-side per viewer and read straight
/// off the payload. Wire names differ from [MessageEntity]'s properties:
/// `content`→`text`, `mediaUrl`→`attachmentUrl`, `createdAt`→`sentAt`.
MessageEntity messageEntityFromWire(
  Map<String, dynamic> json, {
  String? clientMessageId,
}) {
  return MessageEntity(
    id: json['id'] as String,
    conversationId: json['roomId'] as String,
    text: json['content'] as String? ?? '',
    sentAt: DateTime.parse(json['createdAt'] as String),
    isMine: json['isMine'] as bool? ?? false,
    status: messageStatusFromWire(
      json['status'] as String?,
      json['isRead'] as bool? ?? false,
    ),
    type: messageTypeFromWire(json['type'] as String?),
    attachmentUrl: json['mediaUrl'] as String?,
    clientMessageId: clientMessageId ?? json['clientMessageId'] as String?,
    editedAt: json['editedAt'] == null
        ? null
        : DateTime.parse(json['editedAt'] as String),
    replyTo: messageReplyPreviewFromWire(json['replyTo']),
  );
}

/// Decodes the backend's `MessageReplyDto` (or `null`) into a
/// [MessageReplyPreview]. Defensively tolerant of a malformed/missing map —
/// same "drop rather than throw" stance as `RealtimeService._asMap`.
MessageReplyPreview? messageReplyPreviewFromWire(dynamic json) {
  if (json is! Map) return null;
  final map = json.cast<String, dynamic>();
  final id = map['id'] as String?;
  if (id == null) return null;
  return MessageReplyPreview(
    id: id,
    isMine: map['isMine'] as bool? ?? false,
    type: messageTypeFromWire(map['type'] as String?),
    text: map['content'] as String? ?? '',
    attachmentUrl: map['mediaUrl'] as String?,
    isDeleted: map['isDeleted'] as bool? ?? false,
    editedAt: map['editedAt'] == null
        ? null
        : DateTime.parse(map['editedAt'] as String),
  );
}

/// Maps the backend's lowercase delivery status (`sent`/`delivered`/`read`) to
/// [MessageStatus]; falls back to `isRead` for any payload that predates it.
MessageStatus messageStatusFromWire(String? status, bool isRead) =>
    switch (status) {
      'read' => MessageStatus.read,
      'delivered' => MessageStatus.delivered,
      'sent' => MessageStatus.sent,
      _ => isRead ? MessageStatus.read : MessageStatus.sent,
    };

MessageType messageTypeFromWire(String? backendType) => switch (backendType) {
      'IMAGE' => MessageType.image,
      'AUDIO' => MessageType.voice,
      'VIDEO' => MessageType.image,
      _ => MessageType.text,
    };

/// [MessageType] → backend enum. `document` has no backend equivalent, so it
/// degrades to `TEXT`.
String messageTypeToWire(MessageType type) => switch (type) {
      MessageType.text => 'TEXT',
      MessageType.image => 'IMAGE',
      MessageType.voice => 'AUDIO',
      MessageType.document => 'TEXT',
    };
