import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../interests/presentation/widgets/interest_list_view.dart';
import '../../domain/entities/conversation_entity.dart';
import '../providers/inbox_providers.dart';
import '../widgets/conversation_list_view.dart';
import '../widgets/inbox_app_bar.dart';
import '../widgets/inbox_search_bar.dart';
import '../widgets/inbox_selection_scope.dart';
import '../widgets/inbox_tabs.dart';

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
                InboxTab.messages => const _MessagesTabView(
                  key: ValueKey('messages'),
                ),
                InboxTab.interestsReceived => const InterestListView(
                  key: ValueKey('received'),
                  isReceived: true,
                ),
                InboxTab.interestsSent => const InterestListView(
                  key: ValueKey('sent'),
                  isReceived: false,
                ),
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
    return ConversationListView(
      conversations: ref.watch(filteredConversationsProvider),
    );
  }
}
