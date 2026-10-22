import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/navigation/app_bottom_nav.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../interests/presentation/widgets/interest_list_view.dart';
import '../../domain/entities/conversation_entity.dart';
import '../providers/inbox_providers.dart';
import '../widgets/conversation_card.dart';
import '../widgets/empty_inbox.dart';
import '../widgets/inbox_app_bar.dart';
import '../widgets/inbox_search_bar.dart';
import '../widgets/inbox_selection_scope.dart';
import '../widgets/inbox_shimmer.dart';
import '../widgets/inbox_tabs.dart';
import '../widgets/premium_conversation_card.dart';

/// The Inbox — replaces the old placeholder Chat tab. AppBar + search +
/// animated tabs (Interests Received / Interests Sent / Messages) over a
/// scrollable, pull-to-refreshable conversation list.
///
/// Passing [onSelectConversation] puts the page in master-detail mode: a row
/// tap calls it (and [selectedConversationId] marks the open row) instead of
/// pushing the full-screen chat route. Both are optional; without them the page
/// behaves exactly as the single-pane inbox.
class InboxPage extends ConsumerWidget {
  final String? selectedConversationId;
  final ValueChanged<ConversationEntity>? onSelectConversation;

  const InboxPage({
    super.key,
    this.selectedConversationId,
    this.onSelectConversation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTab = ref.watch(inboxTabProvider);

    final page = _buildPage(activeTab);
    final onSelect = onSelectConversation;
    if (onSelect == null) return page;
    return InboxSelectionScope(
      selectedConversationId: selectedConversationId,
      onSelect: onSelect,
      child: page,
    );
  }

  Widget _buildPage(InboxTab activeTab) {
    return Scaffold(
      appBar: const InboxAppBar(),
      body: Column(
        children: [
          const SizedBox(height: 12),
          const InboxSearchBar(),
          const SizedBox(height: 8),
          const InboxTabs(),
          const Divider(height: 1),
          Expanded(
            // Cross-fades between tabs instead of an abrupt swap — each
            // branch keeps its own scroll position via its `ValueKey`
            // (AnimatedSwitcher would otherwise treat same-type children as
            // interchangeable and skip the transition).
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: switch (activeTab) {
                InboxTab.messages => const _MessagesTabView(key: ValueKey('messages')),
                InboxTab.interestsReceived =>
                  const InterestListView(key: ValueKey('received'), isReceived: true),
                InboxTab.interestsSent =>
                  const InterestListView(key: ValueKey('sent'), isReceived: false),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagesTabView extends ConsumerWidget {
  const _MessagesTabView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(filteredConversationsProvider);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => ref.read(conversationsNotifierProvider.notifier).refresh(),
      child: conversationsAsync.when(
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
              children: const [
                SizedBox(height: 48),
                _FadeIn(child: EmptyInbox()),
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
