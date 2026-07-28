import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/realtime/realtime_event.dart';
import '../../../../core/realtime/realtime_providers.dart';
import '../../data/mappers/message_wire_mapper.dart';
import 'inbox_providers.dart';

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
        }

      case ChatRealtimeEvent.typing:
        final roomId = data['roomId'] as String?;
        if (roomId != null) {
          ref
              .read(conversationsNotifierProvider.notifier)
              .setTyping(roomId, data['isTyping'] as bool? ?? false);
        }
    }
  });
  ref.onDispose(subscription.cancel);
});
