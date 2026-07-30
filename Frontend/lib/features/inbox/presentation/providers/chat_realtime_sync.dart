import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/realtime/realtime_event.dart';
import '../../../../core/realtime/realtime_providers.dart';
import '../../data/mappers/message_wire_mapper.dart';
import 'inbox_providers.dart';
import 'presence_providers.dart';

DateTime? _parseLastSeen(dynamic value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toLocal();
}

/// Bridges inbound chat socket events ([RealtimeService.chatEvents]) into the
/// inbox Riverpod state — live messages, edits, deletes, read/delivered
/// receipts, and typing. Watch once at the app root (main.dart) so it lives for
/// the whole session, alongside `realtimeSyncProvider`.
///
/// Thread-level updates (`messagesProvider(roomId)`) are applied only when that
/// thread is open ([chatActiveThreadsProvider]) — an event for an unopened room
/// still updates the conversation list, and the thread picks the change up from
/// a fresh fetch when next opened. The conversation list is updated
/// unconditionally (its unread badge is app-wide).
final chatRealtimeSyncProvider = Provider<void>((ref) {
  final service = ref.watch(realtimeServiceProvider);

  // Seed the live presence cache from each conversation's REST snapshot — once
  // per peer (seed() ignores peers already tracked live), so socket events are
  // never clobbered by a later list refresh. fireImmediately covers an
  // already-loaded list.
  ref.listen(conversationsNotifierProvider, (previous, next) {
    final convs = next.valueOrNull;
    if (convs == null) return;
    final presence = ref.read(presenceProvider.notifier);
    for (final c in convs) {
      presence.seed(c.profile.id, isOnline: c.isOnline, lastSeen: c.lastSeen);
    }
  }, fireImmediately: true);

  bool isThreadOpen(String roomId) =>
      ref.read(chatActiveThreadsProvider).contains(roomId);

  void onOpenThread(String roomId, void Function(MessagesNotifier) apply) {
    if (!isThreadOpen(roomId)) return;
    apply(ref.read(messagesProvider(roomId).notifier));
  }

  final subscription = service.chatEvents.listen((payload) {
    final data = payload.data;
    switch (payload.event) {
      case ChatRealtimeEvent.message:
        final message = messageEntityFromWire(data);
        final open = isThreadOpen(message.conversationId);
        if (open) {
          ref
              .read(messagesProvider(message.conversationId).notifier)
              .applyIncoming(message);
        }
        ref
            .read(conversationsNotifierProvider.notifier)
            .applyIncomingMessage(message, bumpUnread: !open);
        // A message arriving from the peer ends their typing immediately, even
        // if the matching typing_stop hasn't landed yet.
        final senderId = data['senderId'] as String?;
        if (senderId != null && !message.isMine) {
          ref.read(presenceProvider.notifier).setTyping(senderId, false);
        }

      case ChatRealtimeEvent.messageEdited:
        final message = messageEntityFromWire(data);
        onOpenThread(message.conversationId, (n) => n.applyEdited(message));

      case ChatRealtimeEvent.messageDeleted:
        final roomId = data['roomId'] as String?;
        final id = data['id'] as String?;
        if (roomId != null && id != null) {
          onOpenThread(roomId, (n) => n.applyDeleted(id));
        }

      case ChatRealtimeEvent.read:
        // chat.read payload is { id: roomId, at }.
        final roomId = data['id'] as String?;
        if (roomId != null) {
          onOpenThread(roomId, (n) => n.applyPeerRead());
          ref.read(conversationsNotifierProvider.notifier).applyPeerRead(roomId);
        }

      case ChatRealtimeEvent.delivered:
        final roomId = data['roomId'] as String?;
        final id = data['id'] as String?;
        if (roomId != null && id != null) {
          onOpenThread(roomId, (n) => n.applyDelivered(id));
          ref.read(conversationsNotifierProvider.notifier).applyDelivered(roomId);
        }

      case ChatRealtimeEvent.typing:
        // Payload is { roomId, userId, isTyping }. Key typing by the typer's
        // user id in the presence cache (drives the header + list dot), and
        // keep the room-keyed conversation flag in sync for the list.
        final roomId = data['roomId'] as String?;
        final typerId = data['userId'] as String?;
        final isTyping = data['isTyping'] as bool? ?? false;
        if (typerId != null) {
          ref.read(presenceProvider.notifier).setTyping(typerId, isTyping);
        }
        if (roomId != null) {
          ref
              .read(conversationsNotifierProvider.notifier)
              .setTyping(roomId, isTyping);
        }

      case ChatRealtimeEvent.presence:
        // Payload is { userId, isOnline, lastSeenAt }.
        final userId = data['userId'] as String?;
        if (userId != null) {
          ref.read(presenceProvider.notifier).applyPresence(
                userId,
                isOnline: data['isOnline'] as bool? ?? false,
                lastSeen: _parseLastSeen(data['lastSeenAt']),
              );
        }
    }
  });
  ref.onDispose(subscription.cancel);
});
