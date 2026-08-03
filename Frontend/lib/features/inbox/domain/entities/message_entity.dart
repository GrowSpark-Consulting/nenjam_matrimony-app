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

/// A slim, immutable snapshot of the message a [MessageEntity] replies to —
/// enough to render a reply-quote (sender/preview/thumbnail/deleted-or-edited
/// state) without looking the original up. Mirrors the backend's
/// `MessageReplyDto` field-for-field. Built two ways: optimistically, from an
/// already-loaded [MessageEntity] the user long-pressed
/// ([MessageReplyPreview.fromMessage]), or parsed off the wire
/// (`message_wire_mapper.dart`) once the server confirms/echoes it — both
/// paths produce the same shape, so reconciliation never has to special-case
/// which one it's looking at.
class MessageReplyPreview {
  final String id;
  final bool isMine;
  final MessageType type;
  final String text;
  final String? attachmentUrl;
  final bool isDeleted;
  final DateTime? editedAt;

  const MessageReplyPreview({
    required this.id,
    required this.isMine,
    required this.type,
    required this.text,
    this.attachmentUrl,
    this.isDeleted = false,
    this.editedAt,
  });

  factory MessageReplyPreview.fromMessage(MessageEntity message) {
    return MessageReplyPreview(
      id: message.id,
      isMine: message.isMine,
      type: message.type,
      text: message.text,
      attachmentUrl: message.attachmentUrl,
      isDeleted: message.isDeleted,
      editedAt: message.editedAt,
    );
  }
}

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

  /// The message this one replies to, or null. Immutable once set — like
  /// [type]/[sentAt], a message's reply target never changes after it's
  /// created, so it's never a [copyWith] parameter; every [copyWith] call
  /// passes it through unchanged.
  final MessageReplyPreview? replyTo;

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
    this.replyTo,
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
      replyTo: replyTo,
    );
  }
}

/// How long after sending a text message it can still be edited — mirrors
/// the backend's own `EDIT_WINDOW_MS` in `messages.service.ts` (15 minutes).
/// Duplicated here (rather than fetched from the server) so the edit action
/// itself and its UI can both check it without a network round trip; the
/// server re-enforces this independently on every edit request and is
/// always the final word regardless of what the client thinks.
const Duration kMessageEditWindow = Duration(minutes: 15);

bool isMessageEditWindowExpired(DateTime sentAt) =>
    DateTime.now().difference(sentAt) > kMessageEditWindow;

/// Thrown by [MessageEntity]-editing callers (see
/// `MessagesNotifier.edit`) when [isMessageEditWindowExpired] is true for
/// the message being edited — mirrors the backend's own rejection for the
/// same condition, just without the round trip.
class MessageEditWindowExpiredException implements Exception {
  const MessageEditWindowExpiredException();

  String get message => 'This message can no longer be edited.';

  @override
  String toString() => message;
}
