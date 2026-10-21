import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/inbox/domain/entities/conversation_entity.dart';
import '../../features/inbox/presentation/pages/chat_detail_page.dart';
import '../../features/profile_detail/presentation/pages/profile_detail_page.dart';
import '../../l10n/app_localizations.dart';
import '../constants/app_spacing.dart';
import 'profile_navigation.dart';
import 'route_entity_resolvers.dart';
import 'route_names.dart';

/// Body of `/chat-detail/:conversationId`.
///
/// In-app navigation hands over the [ConversationEntity] in `extra` and this
/// renders [ChatDetailPage] immediately, exactly as before. A reload, copied
/// link or bookmark arrives without it; the entity is then looked up by id
/// (see [chatConversationByIdProvider]) with loading, not-found and error
/// states.
class ChatDetailRoutePage extends ConsumerWidget {
  final String conversationId;
  final ConversationEntity? initial;

  const ChatDetailRoutePage({
    super.key,
    required this.conversationId,
    this.initial,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final given = initial;
    if (given != null && given.id == conversationId) {
      return ChatDetailPage(conversation: given);
    }

    final l10n = AppLocalizations.of(context);
    return ref
        .watch(chatConversationByIdProvider(conversationId))
        .when(
          loading: () => const _RouteLoading(),
          error: (_, __) => _RouteMessage(
            message: l10n.inboxLoadError,
            actionLabel: l10n.commonTryAgain,
            onAction: () =>
                ref.invalidate(chatConversationByIdProvider(conversationId)),
            fallbackLabel: l10n.navMessages,
            fallbackRoute: RouteNames.messages,
          ),
          data: (conversation) => conversation == null
              ? _RouteMessage(
                  message: l10n.profileDetailProfileNotAvailable,
                  fallbackLabel: l10n.navMessages,
                  fallbackRoute: RouteNames.messages,
                )
              : ChatDetailPage(conversation: conversation),
        );
  }
}

/// Body of `/profile-detail/:profileId` — same shape as
/// [ChatDetailRoutePage], for profiles. In-app navigation (which carries a
/// [ProfileDetailArgs]) never reaches this; the router renders
/// [ProfileDetailPage] directly for it.
class ProfileDetailRoutePage extends ConsumerWidget {
  final String profileId;

  const ProfileDetailRoutePage({super.key, required this.profileId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref
        .watch(profileByIdProvider(profileId))
        .when(
          loading: () => const _RouteLoading(),
          error: (_, __) => _RouteMessage(
            message: l10n.inboxLoadError,
            actionLabel: l10n.commonTryAgain,
            onAction: () => ref.invalidate(profileByIdProvider(profileId)),
            fallbackLabel: l10n.navDiscover,
            fallbackRoute: RouteNames.discover,
          ),
          data: (profile) => profile == null
              ? _RouteMessage(
                  message: l10n.profileDetailProfileNotAvailable,
                  fallbackLabel: l10n.navDiscover,
                  fallbackRoute: RouteNames.discover,
                )
              : ProfileDetailPage(profile: profile),
        );
  }
}

class _RouteLoading extends StatelessWidget {
  const _RouteLoading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _RouteMessage extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String fallbackLabel;
  final String fallbackRoute;

  const _RouteMessage({
    required this.message,
    required this.fallbackLabel,
    required this.fallbackRoute,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.base),
              if (actionLabel != null)
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              TextButton(
                onPressed: () => context.go(fallbackRoute),
                child: Text(fallbackLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
