import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/window_class.dart';
import '../../../../core/router/route_entity_pages.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/widgets/feedback/empty_state.dart';
import '../../domain/entities/conversation_entity.dart';
import 'inbox_page.dart';

/// The body of both Inbox routes, as one pane or two depending on the room the
/// page is actually given.
///
/// Neither route's registration changes: `/messages` stays in the Inbox shell
/// branch and `/chat-detail/:conversationId` stays a root-level route, so a
/// phone keeps pushing the chat full-screen over the list and back returns to
/// it. Only what the route *renders* varies.
///
/// * **Narrower than [WindowClass.expanded]** -- exactly the pages that existed
///   before: the list on `/messages`, the chat alone on `/chat-detail/:id`.
/// * **Expanded and wider** -- the list beside a detail pane. The detail pane is
///   always a [ChatDetailRoutePage], so conversation lookup, loading, retry and
///   unavailable-conversation handling are the existing ones, not a copy.
///
/// Where the selection lives at expanded widths:
///
/// * `/chat-detail/:id` -- in the URL ([selectedConversationId]). Picking
///   another row `pushReplacement`s to that route, so the URL still names the
///   open conversation, a reload restores it, and the entry underneath (the
///   inbox) is untouched -- repeated picks never grow the back stack.
/// * `/messages` -- in this widget's state, NOT in the URL. Pushing the
///   root-level chat route from here would cover the very list the two-pane
///   layout exists to show. A reload therefore returns to the unselected inbox.
///   The deep-linkable, URL-authoritative form is `/chat-detail/:id`.
///
/// Composer text is local to the chat's `TextEditingController` and is not
/// persisted anywhere; see the [ValueKey] on the detail pane.
class InboxShellPage extends StatefulWidget {
  /// The conversation named by the URL, or null on `/messages`.
  final String? selectedConversationId;

  /// Handed over by in-app navigation; absent after a reload or a copied link,
  /// in which case the chat looks the conversation up by id.
  final ConversationEntity? initialConversation;

  const InboxShellPage({
    super.key,
    this.selectedConversationId,
    this.initialConversation,
  });

  /// Width of the conversation list when it sits beside the detail pane.
  static const double listPaneWidth = 360;

  @override
  State<InboxShellPage> createState() => _InboxShellPageState();
}

class _InboxShellPageState extends State<InboxShellPage> {
  /// Selection made in the list pane on `/messages` (not URL-backed).
  ConversationEntity? _picked;

  void _pick(ConversationEntity conversation) {
    if (conversation.id == _picked?.id) return;
    setState(() => _picked = conversation);
  }

  void _replaceRoute(ConversationEntity conversation) {
    if (conversation.id == widget.selectedConversationId) return;
    context.pushReplacement(
      RouteNames.chatDetailPath(conversation.id),
      extra: conversation,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Local constraints, not MediaQuery: when this sits beside the navigation
    // rail it must see the room it was given, not the window.
    return LayoutBuilder(
      builder: (context, constraints) {
        final routeId = widget.selectedConversationId;

        if (!WindowClass.fromWidth(constraints.maxWidth).isAtLeastExpanded) {
          if (_picked != null) {
            // A pane-only selection means nothing in one-pane mode; drop it so
            // widening later cannot resurrect a stale conversation.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _picked != null) setState(() => _picked = null);
            });
          }
          return routeId == null
              ? const InboxPage()
              : ChatDetailRoutePage(
                  conversationId: routeId,
                  initial: widget.initialConversation,
                );
        }

        final selectedId = routeId ?? _picked?.id;
        final initial = routeId != null ? widget.initialConversation : _picked;

        return Row(
          children: [
            SizedBox(
              width: InboxShellPage.listPaneWidth,
              // Each pane owns its own scrollable, so flinging the list never
              // scrolls the chat and vice versa.
              child: InboxPage(
                selectedConversationId: selectedId,
                onSelectConversation: routeId == null ? _pick : _replaceRoute,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              // The avatar Hero in the list row and the one in the chat header
              // share a tag; two live in one route would assert on the next
              // transition. The list keeps its Hero, the pane gives its up.
              child: HeroMode(
                enabled: false,
                child: selectedId == null
                    ? const NmEmptyState.noMessages()
                    // Load-bearing for correctness: without a per-conversation
                    // key Flutter would reuse the composer's State when the
                    // selection changes, carrying text typed for one person
                    // into another person's thread.
                    : ChatDetailRoutePage(
                        key: ValueKey(selectedId),
                        conversationId: selectedId,
                        initial: initial,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
