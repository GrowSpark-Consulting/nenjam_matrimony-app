import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../domain/entities/conversation_entity.dart';

/// Single entry point for navigating to Chat Detail — mirrors
/// `core/router/profile_navigation.dart`'s `openProfileDetail`, so every
/// conversation-tap call site pushes the same way instead of each one
/// hand-rolling `context.push(RouteNames.chatDetail, extra: ...)`.
void openChatDetail(BuildContext context, ConversationEntity conversation) {
  context.push(RouteNames.chatDetail, extra: conversation);
}
