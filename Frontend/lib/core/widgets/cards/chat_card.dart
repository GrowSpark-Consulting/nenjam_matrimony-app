import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../avatars/app_avatars.dart';
import '../badges/premium_badge.dart';
import '../badges/verification_badge.dart';
import '../feedback/typing_dots.dart';

/// Delivery state of the *last* message, for the read-receipt tick shown
/// next to the timestamp — only relevant when the current user sent it.
enum NmReadStatus { none, sent, delivered, read }

/// Chat card item for conversation list.
///
/// Purely presentational — the Inbox feature's `ConversationCard` configures
/// this from a `ConversationEntity` and adds swipe actions / long-press /
/// Hero / navigation around it, but this stays the single visual definition
/// of "what a conversation row looks like" so nothing else re-implements it.
class NmChatCard extends StatelessWidget {
  final String name;
  final String lastMessage;
  final String time;
  final int unreadCount;
  final bool isOnline;
  final String? avatarUrl;

  /// 'Male' / 'Female' / '' — picks the gender-aware placeholder icon
  /// when [avatarUrl] is null.
  final String gender;
  final VoidCallback? onTap;

  /// Separate tap target for just the avatar (e.g. "avatar -> profile
  /// detail" while the rest of the row opens the chat thread).
  final VoidCallback? onAvatarTap;

  /// e.g. "26 · Chennai · 92% Match" — a second, smaller line above the
  /// last-message preview. Omitted entirely when empty.
  final String subtitleMeta;
  final bool isVerified;
  final bool isPremium;
  final bool isPinned;
  final bool isMuted;
  final bool isTyping;
  final NmReadStatus readStatus;

  /// Optional small chip slot (e.g. a "New Match" indicator) shown above
  /// the name.
  final Widget? indicator;

  /// When set, wraps the avatar in a [Hero] with this tag — matched by the
  /// same tag on the destination page's header avatar for a smooth shared
  /// transition. Omitted (no Hero) when null.
  final Object? heroTag;

  const NmChatCard({
    super.key,
    required this.name,
    required this.lastMessage,
    required this.time,
    this.unreadCount = 0,
    this.isOnline = false,
    this.avatarUrl,
    this.gender = '',
    this.onTap,
    this.onAvatarTap,
    this.subtitleMeta = '',
    this.isVerified = false,
    this.isPremium = false,
    this.isPinned = false,
    this.isMuted = false,
    this.isTyping = false,
    this.readStatus = NmReadStatus.none,
    this.indicator,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;
    final secondaryText = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    final tertiaryText = isDark
        ? AppColors.textTertiaryDark
        : AppColors.textTertiaryLight;
    final unreadTint = isDark
        ? AppColors.primaryLight
        : AppColors.primarySurface;

    final semanticParts = <String>[
      name,
      if (isTyping) 'typing' else lastMessage,
      if (unreadCount > 0) '$unreadCount unread',
    ];

    return Semantics(
      button: onTap != null,
      label: semanticParts.join(', '),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: unreadCount > 0
            ? unreadTint.withValues(alpha: isDark ? 0.14 : 0.4)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onAvatarTap,
                  child: heroTag == null
                      ? NmOnlineAvatar(
                          imageUrl: avatarUrl,
                          isOnline: isOnline,
                          size: 54,
                          gender: gender,
                        )
                      : Hero(
                          tag: heroTag!,
                          child: NmOnlineAvatar(
                            imageUrl: avatarUrl,
                            isOnline: isOnline,
                            size: 54,
                            gender: gender,
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (indicator != null) ...[
                        indicator!,
                        const SizedBox(height: 4),
                      ],
                      Row(
                        children: [
                          if (isPinned) ...[
                            const Icon(
                              Icons.push_pin_rounded,
                              size: 14,
                              color: AppColors.accentGold,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              name,
                              style: AppTypography.titleMedium.copyWith(
                                color: primaryText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const NmVerificationBadge(size: NmBadgeSize.small),
                          ],
                          if (isPremium) ...[
                            const SizedBox(width: 4),
                            const NmPremiumBadge(size: NmBadgeSize.small),
                          ],
                          if (isMuted) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.notifications_off_rounded,
                              size: 14,
                              color: tertiaryText,
                            ),
                          ],
                          const Spacer(),
                          Text(
                            time,
                            style: AppTypography.labelSmall.copyWith(
                              color: unreadCount > 0
                                  ? AppColors.primary
                                  : tertiaryText,
                              fontWeight: unreadCount > 0
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      if (subtitleMeta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitleMeta,
                          style: AppTypography.labelSmall.copyWith(
                            color: secondaryText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (readStatus != NmReadStatus.none) ...[
                            Icon(
                              readStatus == NmReadStatus.sent
                                  ? Icons.check_rounded
                                  : Icons.done_all_rounded,
                              size: 15,
                              color: readStatus == NmReadStatus.read
                                  ? AppColors.verified
                                  : tertiaryText,
                            ),
                            const SizedBox(width: 3),
                          ],
                          Expanded(
                            child: isTyping
                                ? const NmTypingDots(color: AppColors.primary)
                                : Text(
                                    lastMessage,
                                    style: AppTypography.chatMessages.copyWith(
                                      color: unreadCount > 0
                                          ? primaryText
                                          : secondaryText,
                                      fontWeight: unreadCount > 0
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                          if (unreadCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              constraints: const BoxConstraints(minWidth: 22),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                unreadCount > 99 ? '99+' : '$unreadCount',
                                textAlign: TextAlign.center,
                                style: AppTypography.labelSmall.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
