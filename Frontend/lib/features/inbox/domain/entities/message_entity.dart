/// Client-side lifecycle of an outgoing message — `sending` while the send
/// call (upload, for image/voice, then the message POST) is in flight, then
/// `sent`/`delivered`/`read` as the thread's state advances, or `failed` if
/// it errors.
enum MessageStatus { sending, sent, delivered, read, failed }

/// `text`, `image`, and `voice` all send for real against the chat backend
/// (`ConversationRepository.uploadImageAttachment`/`uploadVoiceAttachment`
/// upload the file first, then `sendMessage` with the hosted URL). `document`
/// exists only so [MessageEntity]/message bubbles already know how to render
/// that shape if the mock history ever seeds one; nothing produces it yet.
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

  /// A hosted `http(s)` URL once confirmed, or a local file path while the
  /// optimistic bubble is still `sending`/uploading, for `type ==
  /// image`/`document`/`voice` messages. Null for plain text.
  final String? attachmentUrl;

  /// Recording length for `type == voice` messages — known immediately for
  /// one this client just recorded, or derived on playback (decoded from
  /// the audio file) for one arriving from elsewhere. Like
  /// [clientMessageId], this has NO backing `ChatMessage` column — it's
  /// never sent to or read from the backend, purely a local/derived display
  /// value. Null for every other type.
  final Duration? voiceDuration;

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

  /// When the sender last edited this message's text, or null if never edited.
  /// The bubble shows an "edited" marker when set. Maps from the backend's
  /// `editedAt` field.
  final DateTime? editedAt;

  /// True once the sender deleted the message for everyone. The row is kept so
  /// the bubble can render a "message deleted" tombstone in place rather than
  /// vanishing. Set live from a `chat.messageDeleted` push; deleted messages
  /// are simply absent from a fresh history fetch (the backend filters them).
  final bool isDeleted;

  const MessageEntity({
    required this.id,
    required this.conversationId,
    required this.text,
    required this.sentAt,
    required this.isMine,
    this.status = MessageStatus.sent,
    this.type = MessageType.text,
    this.attachmentUrl,
    this.voiceDuration,
    this.clientMessageId,
    this.editedAt,
    this.isDeleted = false,
  });

  MessageEntity copyWith({
    String? id,
    String? text,
    MessageStatus? status,
    String? attachmentUrl,
    Duration? voiceDuration,
    DateTime? editedAt,
    bool? isDeleted,
  }) {
    return MessageEntity(
      id: id ?? this.id,
      conversationId: conversationId,
      text: text ?? this.text,
      sentAt: sentAt,
      isMine: isMine,
      status: status ?? this.status,
      type: type,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      clientMessageId: clientMessageId,
      editedAt: editedAt ?? this.editedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
