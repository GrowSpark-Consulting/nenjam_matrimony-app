import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../entities/conversation_entity.dart';
import '../entities/message_entity.dart';
import 'package:cross_file/cross_file.dart';

/// Thrown by [ConversationRepository.uploadVoiceAttachment] when there is no
/// working chat attachment-upload endpoint to send a recording to — see
/// that method's doc comment. Never thrown as a "fake" failure; it means
/// exactly what it says.
class MediaUploadUnavailableException implements Exception {
  const MediaUploadUnavailableException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A single page of a conversation's messages, oldest-to-newest within the
/// page. [page] 1 is the most recent slice (what a freshly-opened thread
/// shows); increasing [page] moves further into the past — i.e. what
/// scrolling up to load older history requests next.
class MessagePage {
  const MessagePage({
    required this.items,
    required this.page,
    required this.hasMore,
    this.nextCursor,
  });

  final List<MessageEntity> items;
  final int page;

  /// Whether an older page still exists beyond this one.
  final bool hasMore;

  /// Opaque keyset cursor for the next-older page — pass it back as
  /// [ConversationRepository.getMessages]'s `cursor` to continue in keyset
  /// mode, which stays correct even if new messages arrive mid-scroll
  /// (unlike plain offset paging, where a concurrent insert can shift the
  /// window and reproduce an already-loaded message). Null when the
  /// repository doesn't support keyset mode (e.g. the in-memory mock), in
  /// which case callers fall back to [page].
  final String? nextCursor;
}

/// A single page of the conversations list — mirrors
/// `features/matches/domain/repositories/matches_repository.dart`'s
/// `MatchesResultPage` shape for consistency across list features.
class ConversationResultPage {
  const ConversationResultPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  final List<ConversationEntity> items;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;
}

/// Pure abstract Dart interface. The concrete implementation lives in
/// `data/`: [ConversationApiRepositoryImpl], wired via
/// `conversationRepositoryProvider` — it talks to the real chat backend
/// under `backend/apps/api/src/modules/chat/`.
abstract interface class ConversationRepository {
  Future<ConversationResultPage> getConversations({int page = 1, int limit = 20});

  /// Resolves the conversation with [profile] — the caller (Profile
  /// Detail's Message action, once an interest is accepted) already knows
  /// *who* to message but not necessarily which [ConversationEntity.id]
  /// that maps to. Returns the existing conversation if one's already
  /// started, otherwise creates one. Callers MUST only invoke this once
  /// the relationship is actually chat-eligible (an accepted interest) —
  /// this method itself does not re-check that; see
  /// docs/development/chat-backend-handoff.md for why a real backend
  /// implementation has to enforce it server-side regardless of what the
  /// frontend checks first.
  Future<ConversationEntity> getOrCreateConversation(DiscoveryProfileEntity profile);

  /// [cursor], when supplied (even as an empty string), opts into keyset
  /// pagination — pass [MessagePage.nextCursor] back in on the following
  /// call to walk further into the past. Omit it to use legacy offset
  /// (`page`/`limit`) paging. See [MessagePage.nextCursor].
  Future<MessagePage> getMessages(
    String conversationId, {
    int page = 1,
    int limit = 30,
    String? cursor,
  });

  /// [clientMessageId], when supplied, must be echoed back unchanged on the
  /// returned [MessageEntity] — see that field's doc comment for why. [type]/
  /// [attachmentUrl] together describe a non-text message (an image today);
  /// leave both at their defaults for plain text. [replyToMessageId], when
  /// supplied, must be an existing message id in this same conversation —
  /// the server re-validates this regardless of what the caller sends (see
  /// `MessagesService.send`'s reply-target check).
  Future<MessageEntity> sendMessage(
    String conversationId,
    String text, {
    String? clientMessageId,
    MessageType type,
    String? attachmentUrl,
    String? replyToMessageId,
  });

  /// Uploads a local voice-note recording and returns its hosted media URL
  /// — call this BEFORE [sendMessage] for `type == MessageType.voice`,
  /// mirroring the existing "upload attachment, then POST the message"
  /// pattern already proposed for images (see
  /// docs/development/chat-backend-handoff.md, §5.8). There is no real
  /// endpoint for this yet on either implementation: the mock always throws
  /// [MediaUploadUnavailableException] — there is nothing legitimate to
  /// fake — and the API implementation attempts a real call to the
  /// proposed (not-yet-registered) endpoint, so it fails for real rather
  /// than pretending. Callers must never treat [localFilePath] itself as a
  /// sendable `attachmentUrl`.
  Future<String> uploadVoiceAttachment(String localFilePath);

  /// Uploads a local image attachment and returns its hosted media URL —
  /// call this BEFORE [sendMessage] for `type == MessageType.image`, the
  /// same upload-first pattern as [uploadVoiceAttachment]. Callers must
  /// never hand [localFilePath] itself to [sendMessage] as if it were
  /// already a hosted URL.
  Future<String> uploadImageAttachment(XFile file);

  Future<void> pin(String conversationId, bool pinned);

  Future<void> mute(String conversationId, bool muted);

  Future<void> archive(String conversationId, bool archived);

  Future<void> block(String conversationId, bool blocked);

  Future<void> delete(String conversationId);

  Future<void> markRead(String conversationId);

  Future<void> markUnread(String conversationId);

  /// Edits a text message's content. Only the sender may edit, only text
  /// messages, and only within the backend's edit window — the server enforces
  /// all three and returns the updated message (with `editedAt` set). The peer
  /// is notified live via a `chat.messageEdited` push.
  Future<MessageEntity> editMessage(String messageId, String content);

  /// Deletes a message for everyone (soft delete). Only the sender may delete.
  /// The peer is notified live via a `chat.messageDeleted` push.
  Future<void> deleteMessage(String messageId);

  /// Signals this client's own typing state for [conversationId] so the
  /// backend can relay it to the other participant. Carried over the realtime
  /// socket rather than REST (see [ConversationApiRepositoryImpl.setTyping]);
  /// a down socket is a no-op, since typing is ephemeral and there is
  /// nothing to reconcile afterwards.
  Future<void> setTyping(String conversationId, bool isTyping);

  /// Re-presigns [messageId]'s media URL — call when an image fails to load
  /// with a 403 (its previous presigned URL expired; these are always
  /// short-lived, never permanent public links). Returns null if the
  /// message has no media or presigning failed server-side; never throws
  /// for either of those — this is a best-effort background refresh, not a
  /// critical action, so a caller should treat null the same as a thrown
  /// error (fall back to showing the image as broken).
  Future<String?> refreshMediaUrl(String messageId);
}
