import 'package:flutter/widgets.dart';

import '../../domain/entities/conversation_entity.dart';

/// Tells the conversation rows beneath it that the Inbox is being shown beside
/// a detail pane, so a tap should *select* the conversation there instead of
/// pushing the full-screen chat route over the whole list.
///
/// Absent on compact widths, where rows keep pushing the chat route exactly as
/// they always have.
class InboxSelectionScope extends InheritedWidget {
  /// The conversation currently shown in the detail pane, if any.
  final String? selectedConversationId;

  /// Called when a row is tapped while the detail pane is visible.
  final ValueChanged<ConversationEntity> onSelect;

  const InboxSelectionScope({
    super.key,
    required this.selectedConversationId,
    required this.onSelect,
    required super.child,
  });

  /// The nearest scope, or null when the Inbox is a single full-screen pane.
  static InboxSelectionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InboxSelectionScope>();

  @override
  bool updateShouldNotify(InboxSelectionScope oldWidget) =>
      selectedConversationId != oldWidget.selectedConversationId ||
      onSelect != oldWidget.onSelect;
}
