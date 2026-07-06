import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Empty state placeholder widget.
class NmEmptyState extends StatelessWidget {
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  const NmEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_rounded,
    this.action,
  });

  /// No matches found.
  const NmEmptyState.noMatches({
    super.key,
    this.action,
  })  : title = 'No Matches Found',
        message = 'Try adjusting your preferences to discover more profiles.',
        icon = Icons.favorite_border_rounded;

  /// No messages.
  const NmEmptyState.noMessages({
    super.key,
    this.action,
  })  : title = 'No Messages Yet',
        message = 'Start a conversation with someone you like!',
        icon = Icons.chat_bubble_outline_rounded;

  /// No notifications.
  const NmEmptyState.noNotifications({
    super.key,
    this.action,
  })  : title = 'All Caught Up!',
        message = 'You have no new notifications.',
        icon = Icons.notifications_none_rounded;

  /// No search results.
  const NmEmptyState.noResults({
    super.key,
    this.action,
  })  : title = 'No Results',
        message = 'Try different search terms or filters.',
        icon = Icons.search_off_rounded;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceVariantDark
                    : AppColors.surfaceVariantLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: AppTypography.bodyMedium.copyWith(
                  color: isDark
                      ? AppColors.textTertiaryDark
                      : AppColors.textTertiaryLight,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
