/// Client-side lifecycle of an outgoing message — `sending` while the
/// (currently mocked) send call is in flight, then `sent`/`delivered`/`read`
/// as the thread's state advances, or `failed` if it errors.
enum MessageStatus { sending, sent, delivered, read, failed }

/// Only `text` is actually composable today — `image`/`document`/`voice`
/// exist so [MessageEntity]/message bubbles already know how to render the
/// mock history's non-text entries and so the composer's attachment/voice
/// buttons have a real type to hand off to once they're wired to a backend.
enum MessageType { text, image, document, voice }

/// A single message inside a [ConversationEntity]'s thread.
class MessageEntity {
  final String id;
  final String conversationId;
  final String text;
  final DateTime sentAt;
  final bool isMine;
  final MessageStatus status;
  final MessageType type;

  const MessageEntity({
    required this.id,
    required this.conversationId,
    required this.text,
    required this.sentAt,
    required this.isMine,
    this.status = MessageStatus.sent,
    this.type = MessageType.text,
  });

  MessageEntity copyWith({MessageStatus? status}) {
    return MessageEntity(
      id: id,
      conversationId: conversationId,
      text: text,
      sentAt: sentAt,
      isMine: isMine,
      status: status ?? this.status,
      type: type,
    );
  }
}
