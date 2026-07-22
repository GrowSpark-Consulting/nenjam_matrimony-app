import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/feedback/pulse_dot.dart';

/// Standalone green "online" dot + optional "Online"/last-seen label — used
/// in the Chat Detail header, where the avatar-embedded dot
/// (`NmOnlineAvatar`, drawn inside `NmChatCard` for the list rows) isn't
/// in play.
class OnlineIndicator extends StatelessWidget {
  final bool isOnline;
  /// Already-localized "Online" label, shown when [isOnline] is true.
  final String onlineLabel;
  /// Already-localized last-seen text (e.g. "Last seen yesterday"), shown
  /// when [isOnline] is false. Nothing renders if also null.
  final String? lastSeenLabel;

  const OnlineIndicator({
    super.key,
    required this.isOnline,
    required this.onlineLabel,
    this.lastSeenLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOnline && lastSeenLabel == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isOnline) const NmPulseDot(size: 8, color: AppColors.online),
        if (isOnline) const SizedBox(width: 6),
        Text(
          isOnline ? onlineLabel : (lastSeenLabel ?? ''),
          style: AppTypography.labelSmall.copyWith(
            color: isOnline ? AppColors.online : AppColors.textTertiaryLight,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
