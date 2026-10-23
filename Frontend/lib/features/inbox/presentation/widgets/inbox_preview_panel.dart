import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/inbox_providers.dart';
import 'conversation_list_view.dart';

/// The Inbox's conversation list as a side panel, for Discover on wide screens.
///
/// Rows are the Inbox's own conversation cards in the Inbox's default order,
/// and a tap opens the existing chat route. Search, tabs and filters stay on
/// the Inbox page, and nothing here is selected or kept open — so there is no
/// second chat and no selection state to keep in step with the real Inbox.
class InboxPreviewPanel extends ConsumerWidget {
  static const double width = 320;

  /// Matches Discover's app bar so the panel header and the feed header align.
  static const double _headerHeight = 64;

  const InboxPreviewPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    // A Material rather than a ColoredBox so the rows' ink splashes paint on
    // the panel instead of on the page underneath it.
    return Material(
      color: AppColors.surfaceLight,
      child: SafeArea(
        left: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _headerHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.inboxTitle,
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 20,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ConversationListView(
                conversations: ref.watch(inboxPreviewConversationsProvider),
                showEmptyAction: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
