import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/tokens/app_animation_tokens.dart';

/// Small animated count pill — used on the Inbox tabs (unread/received/sent
/// counts). [ConversationCard]'s own row badge is drawn by `NmChatCard`
/// directly since it's part of that card's fixed layout, not a floating
/// overlay like this one.
class UnreadBadge extends StatelessWidget {
  final int count;

  const UnreadBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: count > 0 ? 1 : 0,
      duration: AppAnimationTokens.fast,
      curve: Curves.easeOutBack,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        constraints: const BoxConstraints(minWidth: 20),
        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
        child: Text(
          count > 99 ? '99+' : '$count',
          textAlign: TextAlign.center,
          style: AppTypography.labelSmall.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
