import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/navigation/app_bottom_nav.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/conversation_entity.dart';
import '../providers/inbox_providers.dart';
import 'conversation_card.dart';
import 'empty_inbox.dart';
import 'inbox_shimmer.dart';
import 'premium_conversation_card.dart';

/// The conversation rows with their loading, error and empty states and
/// pull-to-refresh — one implementation for every place a conversation list
/// is shown, so each renders and refreshes the same way.
///
/// [conversations] decides *which* rows; refreshing always reloads the single
/// shared [conversationsNotifierProvider] they are derived from.
class ConversationListView extends ConsumerWidget {
  final AsyncValue<List<ConversationEntity>> conversations;

  /// Passed through to [EmptyInbox.showAction].
  final bool showEmptyAction;

  const ConversationListView({
    super.key,
    required this.conversations,
    this.showEmptyAction = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () =>
          ref.read(conversationsNotifierProvider.notifier).refresh(),
      child: conversations.when(
        loading: () => const InboxShimmer(),
        error: (error, _) => ListView(
          children: [
            const SizedBox(height: 80),
            Center(child: Text(AppLocalizations.of(context).inboxLoadError)),
          ],
        ),
        data: (conversations) {
          if (conversations.isEmpty) {
            return ListView(
              // Keeps RefreshIndicator's pull-to-refresh working even when
              // the empty state doesn't otherwise fill/scroll the viewport.
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 48),
                _FadeIn(child: EmptyInbox(showAction: showEmptyAction)),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            // Bottom padding clears the floating nav pill, which is drawn over
            // this list — without it the last conversation cannot be scrolled
            // out from under the pill.
            padding: EdgeInsets.fromLTRB(0, 8, 0, navContentInset(context)),
            // A conversation row is comfortably taller than the default
            // 250px lookahead — widen it so swiping/scrolling never briefly
            // shows an unbuilt gap on a fast fling.
            scrollCacheExtent: const ScrollCacheExtent.pixels(600),
            itemCount: conversations.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 90),
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              return RepaintBoundary(
                key: ValueKey(conversation.id),
                child: conversation.isLocked
                    ? PremiumConversationCard(conversation: conversation)
                    : ConversationCard(conversation: conversation),
              );
            },
          );
        },
      ),
    );
  }
}

/// One-shot fade-in on first build — used for the empty state so it settles
/// in gently instead of popping in the instant the list resolves to zero
/// items.
class _FadeIn extends StatefulWidget {
  final Widget child;

  const _FadeIn({required this.child});

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> {
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _opacity = 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      child: widget.child,
    );
  }
}
