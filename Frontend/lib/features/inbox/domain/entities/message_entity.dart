/// Client-side lifecycle of an outgoing message — `sending` while the
/// (currently mocked) send call is in flight, then `sent`/`delivered`/`read`
/// as the thread's state advances, or `failed` if it errors.
enum MessageStatus { sending, sent, delivered, read, failed }

/// Only `text` and `image` are actually composable today — `document`/
/// `voice` exist so [MessageEntity]/message bubbles already know how to
/// render the mock history's non-text entries and so the composer's
/// document/voice affordances have a real type to hand off to once they're
/// wired to a backend.
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

  /// URL (or, before a real upload endpoint exists, a local file path) for
  /// `type == image`/`document`/`voice` messages. Null for plain text.
  final String? attachmentUrl;

  /// Client-generated id set on an outgoing message the moment it's
  /// optimistically appended to the thread — a real backend is expected to
  /// echo this back on the confirmed message so [MessagesNotifier] can match
  /// "the optimistic bubble I just showed" to "the server's response for
  /// it" without relying on either side's own `id` staying stable across
  /// that round trip (the server assigns its own `id`; over a socket, the
  /// confirmation may not even arrive as a direct response to the send
  /// call). Null for messages that were never optimistic — i.e. anything
  /// fetched from history rather than sent by this client this session.
  final String? clientMessageId;

  const MessageEntity({
    required this.id,
    required this.conversationId,
    required this.text,
    required this.sentAt,
    required this.isMine,
    this.status = MessageStatus.sent,
    this.type = MessageType.text,
    this.attachmentUrl,
    this.clientMessageId,
  });

  MessageEntity copyWith({
    String? id,
    MessageStatus? status,
    String? attachmentUrl,
  }) {
    return MessageEntity(
      id: id ?? this.id,
      conversationId: conversationId,
      text: text,
      sentAt: sentAt,
      isMine: isMine,
      status: status ?? this.status,
      type: type,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      clientMessageId: clientMessageId,
    );
  }
}
