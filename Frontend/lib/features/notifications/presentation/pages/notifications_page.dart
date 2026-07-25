import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/feedback_cards.dart';
import '../../../../core/widgets/feedback/empty_state.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/notification_entity.dart';
import '../providers/notification_providers.dart';
import '../utils/notification_time_format.dart';

/// Notifications center screen — reached from the Discover bell (and the
/// Inbox app bar's own bell). Real state: `notificationsNotifierProvider`
/// backs the list (mock-repository-backed today, see
/// `notification_providers.dart`'s doc comment for the backend swap point),
/// so read/unread here immediately drives the Discover bell's badge too.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notificationsAsync = ref.watch(notificationsNotifierProvider);
    final unreadCount = ref.watch(unreadNotificationsCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.notificationsTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          TextButton(
            onPressed: unreadCount > 0
                ? () => ref.read(notificationsNotifierProvider.notifier).markAllRead()
                : null,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(
              l10n.notificationsMarkAllRead,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: notificationsAsync.when(
          data: (items) => items.isEmpty
              ? _EmptyView(l10n: l10n)
              : RefreshIndicator(
                  onRefresh: () => ref.read(notificationsNotifierProvider.notifier).refresh(),
                  child: _NotificationList(items: items, l10n: l10n),
                ),
          loading: () => const _LoadingView(),
          error: (error, _) => NmErrorWidget(
            onRetry: () => ref.read(notificationsNotifierProvider.notifier).refresh(),
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) => const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NmShimmer.circle(size: 40),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NmShimmer(height: 14, width: 160),
                SizedBox(height: 8),
                NmShimmer(height: 12),
                SizedBox(height: 8),
                NmShimmer(height: 10, width: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final AppLocalizations l10n;
  const _EmptyView({required this.l10n});

  @override
  Widget build(BuildContext context) {
    // Scrollable even when empty so RefreshIndicator/pull-to-refresh still
    // works from this state, not just once items exist.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: NmEmptyState(
            title: l10n.notificationsEmptyTitle,
            message: l10n.notificationsEmptyMessage,
            icon: Icons.notifications_none_rounded,
          ),
        ),
      ),
    );
  }
}

class _NotificationList extends ConsumerWidget {
  final List<NotificationEntity> items;
  final AppLocalizations l10n;
  const _NotificationList({required this.items, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Items already arrive newest-first from the repository — group
    // without re-sorting so section order and in-section order both stay
    // stable.
    final sections = <NotificationDateSection, List<NotificationEntity>>{};
    for (final item in items) {
      sections.putIfAbsent(notificationSectionFor(item.createdAt), () => []).add(item);
    }

    final orderedSections = [
      NotificationDateSection.today,
      NotificationDateSection.yesterday,
      NotificationDateSection.earlier,
    ].where((s) => sections[s]?.isNotEmpty ?? false).toList();

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: orderedSections.length,
      itemBuilder: (context, sectionIndex) {
        final section = orderedSections[sectionIndex];
        final sectionItems = sections[section]!;
        return Padding(
          padding: EdgeInsets.only(bottom: sectionIndex == orderedSections.length - 1 ? 0 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 4),
                child: Text(
                  notificationSectionLabel(section, l10n),
                  style: AppTypography.labelLarge.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (var i = 0; i < sectionItems.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _NotificationTile(notification: sectionItems[i], l10n: l10n),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final NotificationEntity notification;
  final AppLocalizations l10n;
  const _NotificationTile({required this.notification, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NmNotificationCard(
      title: notification.title,
      subtitle: notification.message,
      time: formatNotificationTime(notification.createdAt, l10n),
      icon: _iconFor(notification.type),
      isUnread: !notification.isRead,
      avatarUrl: notification.actor != null ? (notification.actor!.photoUrl ?? '') : null,
      onTap: () => _handleTap(context, ref),
    );
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    if (!notification.isRead) {
      await ref.read(notificationsNotifierProvider.notifier).markRead(notification.id);
    }
    if (!context.mounted) return;

    // Only destinations that are safely reachable with no extra data are
    // wired now — Interests/Shortlist/Matches/Chat screens are out of scope
    // for this task (see notifications feature README-equivalent doc
    // comment on NotificationType), so those show a lightweight "coming
    // soon" notice instead of a fake/broken route. This switch is the one
    // place a future route gets added, one line at a time.
    switch (notification.type) {
      case NotificationType.profileCompletionReminder:
        context.push(RouteNames.profileCompletion);
      case NotificationType.verificationUpdate:
        context.push(RouteNames.verification);
      case NotificationType.system:
        break;
      case NotificationType.interestReceived:
      case NotificationType.interestAccepted:
      case NotificationType.interestDeclined:
      case NotificationType.profileLiked:
      case NotificationType.profileViewed:
      case NotificationType.shortlisted:
      case NotificationType.newMatch:
      case NotificationType.messageReceived:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.notificationsComingSoon)),
        );
    }
  }

  IconData _iconFor(NotificationType type) {
    switch (type) {
      case NotificationType.interestReceived:
      case NotificationType.interestAccepted:
        return Icons.favorite_rounded;
      case NotificationType.interestDeclined:
        return Icons.heart_broken_rounded;
      case NotificationType.profileLiked:
        return Icons.thumb_up_rounded;
      case NotificationType.profileViewed:
        return Icons.visibility_rounded;
      case NotificationType.shortlisted:
        return Icons.bookmark_rounded;
      case NotificationType.newMatch:
        return Icons.favorite_rounded;
      case NotificationType.messageReceived:
        return Icons.chat_bubble_rounded;
      case NotificationType.profileCompletionReminder:
        return Icons.auto_awesome_rounded;
      case NotificationType.verificationUpdate:
        return Icons.verified_user_rounded;
      case NotificationType.system:
        return Icons.notifications_rounded;
    }
  }
}
