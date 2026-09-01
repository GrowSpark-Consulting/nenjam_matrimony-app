import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/tokens/app_animation_tokens.dart';
import '../../../../core/theme/tokens/app_touch_target.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../interests/presentation/providers/interests_provider.dart';
import '../providers/inbox_providers.dart';
import 'unread_badge.dart';

const double _kIndicatorWidth = 32;
const double _kIndicatorHeight = 3;

/// Animated segmented tab row — Interests Received / Interests Sent /
/// Messages — with live badge counts. Selection persists via
/// [inboxTabProvider] (a Riverpod `StateProvider`, so it survives widget
/// rebuilds the same way any other piece of app state does).
///
/// The magenta active-indicator is a single bar that *slides* continuously
/// between tabs (`AnimatedPositioned` over a `Stack`, sized from the
/// measured row width) rather than three independent grow/shrink bars —
/// the same visual language as a real `TabBar` indicator, and smoother
/// than each tab fading its own bar in and out.
class InboxTabs extends ConsumerWidget {
  const InboxTabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final activeTab = ref.watch(inboxTabProvider);
    final receivedCount =
        ref.watch(receivedInterestsProvider).valueOrNull?.length ?? 0;
    final sentCount = ref.watch(sentInterestsProvider).valueOrNull?.length ?? 0;
    final unreadCount = ref.watch(unreadConversationsCountProvider);

    final tabs = [
      (
        tab: InboxTab.interestsReceived,
        label: l10n.inboxTabInterestsReceived,
        count: receivedCount,
      ),
      (
        tab: InboxTab.interestsSent,
        label: l10n.inboxTabInterestsSent,
        count: sentCount,
      ),
      (
        tab: InboxTab.messages,
        label: l10n.inboxTabMessages,
        count: unreadCount,
      ),
    ];
    final activeIndex = tabs.indexWhere((t) => t.tab == activeTab);

    return LayoutBuilder(
      builder: (context, constraints) {
        final tabWidth = constraints.maxWidth / tabs.length;
        return Stack(
          children: [
            Row(
              children: [
                for (final t in tabs)
                  Expanded(
                    child: _InboxTab(
                      label: t.label,
                      count: t.count,
                      isActive: activeTab == t.tab,
                      onTap: () =>
                          ref.read(inboxTabProvider.notifier).state = t.tab,
                    ),
                  ),
              ],
            ),
            AnimatedPositioned(
              duration: AppAnimationTokens.normal,
              curve: Curves.easeOutCubic,
              left: tabWidth * activeIndex + (tabWidth - _kIndicatorWidth) / 2,
              bottom: 0,
              width: _kIndicatorWidth,
              height: _kIndicatorHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InboxTab extends StatelessWidget {
  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _InboxTab({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = AppColors.primary;
    const inactiveColor = AppColors.textSecondaryLight;

    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouchTarget.minSize),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: AnimatedDefaultTextStyle(
                      duration: AppAnimationTokens.fast,
                      style: AppTypography.labelMedium.copyWith(
                        color: isActive ? activeColor : inactiveColor,
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Always in the tree — [UnreadBadge] animates its own
                  // scale between 0 and 1 as `count` crosses zero, which
                  // only plays if the widget persists across that change
                  // rather than being inserted/removed by an `if` here.
                  UnreadBadge(count: count),
                ],
              ),
              // Reserves the same vertical space the sliding indicator bar
              // (drawn by the parent `Stack`, not per-tab) occupies, so
              // every tab's content sits at an identical height regardless
              // of which one is active.
              const SizedBox(height: 6 + _kIndicatorHeight),
            ],
          ),
        ),
      ),
    );
  }
}
