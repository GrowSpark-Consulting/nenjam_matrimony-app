import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/discover/domain/entities/discovery_profile_entity.dart';
import '../../features/discover/presentation/providers/discover_providers.dart';
import '../../features/inbox/domain/entities/conversation_entity.dart';
import '../../features/inbox/presentation/providers/inbox_providers.dart';

/// Looks up the conversation named by a `/chat-detail/:conversationId` URL
/// when the router was not handed the entity itself (a browser refresh, a
/// copied link, a bookmark).
///
/// The backend has no `GET /chat/conversations/:id`, so this is a lookup in
/// the member's own conversation list — fetched if it has not been loaded yet,
/// and re-fetched once if the id is not in it (a thread started after the list
/// was last loaded). Resolving to null means "not one of this member's
/// conversations": the list only ever contains threads they participate in, so
/// someone else's id can never resolve. Backend or network failure is thrown,
/// so the page can offer a retry instead of claiming the thread does not exist.
final chatConversationByIdProvider = FutureProvider.autoDispose
    .family<ConversationEntity?, String>((ref, conversationId) async {
      ConversationEntity? find(List<ConversationEntity> all) {
        for (final c in all) {
          if (c.id == conversationId) return c;
        }
        return null;
      }

      final loaded = await ref.watch(conversationsNotifierProvider.future);
      final hit = find(loaded);
      if (hit != null) return hit;

      await ref.read(conversationsNotifierProvider.notifier).refresh();
      return find(
        ref.read(conversationsNotifierProvider).valueOrNull ?? const [],
      );
    });

/// Looks up the profile named by a `/profile-detail/:profileId` URL when the
/// router was not handed the entity itself (a browser refresh, a copied link).
///
/// A profile already in memory — the loaded Discover feed or the member's
/// conversations — is used without a request. Otherwise it is fetched with
/// `GET /discover/profiles/:id`, which applies the feed's own visibility rules
/// on the server. Null means "not available to this member" (the server's
/// uniform 404: missing, deleted, blocked and ineligible are indistinguishable);
/// a network or server failure is thrown so the page can offer a retry.
final profileByIdProvider = FutureProvider.autoDispose
    .family<DiscoveryProfileEntity?, String>((ref, profileId) async {
      final feed = ref.read(discoverFeedProvider).valueOrNull;
      if (feed != null) {
        for (final section in [
          feed.aiRecommended,
          feed.recentlyJoined,
          feed.verifiedProfiles,
          feed.nearYou,
          feed.premiumMembers,
        ]) {
          for (final profile in section) {
            if (profile.id == profileId) return profile;
          }
        }
      }
      final conversations =
          ref.read(conversationsNotifierProvider).valueOrNull ?? const [];
      for (final c in conversations) {
        if (c.profile.id == profileId) return c.profile;
      }

      return ref.read(profileByIdRepositoryProvider).get(profileId);
    });
