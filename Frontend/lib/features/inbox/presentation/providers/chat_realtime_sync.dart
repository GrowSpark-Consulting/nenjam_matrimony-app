import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/realtime/realtime_event.dart';
import '../../../../core/realtime/realtime_providers.dart';
import '../../../../core/utils/server_time.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../data/mappers/message_wire_mapper.dart';
import 'inbox_providers.dart';
import 'presence_providers.dart';

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

  // Reconciles the live presence cache from each conversation's REST
  // snapshot every time the list changes (initial load, pull-to-refresh,
  // and — via the listener below — every socket reconnect). See
  // `PresenceNotifier.seed`'s doc comment: this is a genuine reconcile, not
  // a one-time seed, so a peer's presence can never permanently drift from
  // reality just because a live `chat.presence` broadcast was missed.
  ref.listen(conversationsNotifierProvider, (previous, next) {
    final convs = next.valueOrNull;
    if (convs == null) return;
    final presence = ref.read(presenceProvider.notifier);
    for (final c in convs) {
      presence.seed(c.profile.id, isOnline: c.isOnline, lastSeen: c.lastSeen);
    }
  }, fireImmediately: true);

  // Every reconnect (initial connect and every successful resume after a
  // drop) refreshes the conversations list — the one round trip that
  // reconciles presence for every peer at once, so a stretch of being
  // disconnected (backgrounded, network loss, a dead connection only
  // Socket.IO's own ping-timeout eventually notices) can't leave presence
  // stale until something else happens to touch it.
  final readySubscription = service.onReady.listen((_) {
    unawaited(ref.read(conversationsNotifierProvider.notifier).refresh());
    // The conversations-list refresh above reconciles presence and each
    // room's OWN last-message status for every peer, but a thread that's
    // currently open reads its per-message delivery/read ticks from
    // `messagesProvider`, which doesn't refetch on its own just because the
    // socket reconnected. Without this, a sender who was offline exactly
    // when their message's delivered/read status changed (their own
    // `chat.delivered`/`chat.read` broadcast arrived while they had no
    // live connection to receive it) would see that tick stuck at "Sent"
    // indefinitely in an already-open thread — not just delayed. Resyncing
    // just the newest page and merging it (see `MessagesNotifier.
    // resyncLatest`) picks up any such change without resetting pagination
    // state or scroll position.
    for (final roomId in ref.read(chatActiveThreadsProvider)) {
      unawaited(ref.read(messagesProvider(roomId).notifier).resyncLatest());
    }
  });
  ref.onDispose(readySubscription.cancel);

  // Every cached peer belongs to the session that just ended — wipe it on
  // sign-out so it can't leak stale (or simply wrong) presence into
  // whichever account signs in next on this device, before fresh data
  // arrives for each peer again.
  ref.listen<Object?>(currentAuthUserProvider, (previous, next) {
    if (next == null) ref.read(presenceProvider.notifier).clear();
  });

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
          // Explicit delivery acknowledgment — the authoritative "delivered"
          // signal (see ChatClientEvent.deliveredAck's doc comment), sent the
          // moment this client actually processes the push, regardless of
          // whether the server's presence-based guess at send time already
          // (maybe wrongly) marked it delivered. Harmless no-op server-side
          // if it did guess right, or if this is a reconnect-replay of an
          // already-delivered message.
          service.emit(ChatClientEvent.deliveredAck, {'messageId': message.id});
        }

      case ChatRealtimeEvent.messageEdited:
        final message = messageEntityFromWire(data);
        onOpenThread(message.conversationId, (n) => n.applyEdited(message));
        // Unconditional (unlike the thread-content update above) — the
        // conversation list's preview must reflect an edit even when this
        // thread isn't open, exactly like a new message's preview already
        // does in the case above.
        ref
            .read(conversationsNotifierProvider.notifier)
            .applyEditedMessage(message.conversationId, message);

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
                lastSeen: tryParseServerTime(data['lastSeenAt']),
              );
        }
    }
  });
  ref.onDispose(subscription.cancel);
});
