import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../../core/router/profile_navigation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/cards/chat_card.dart';
import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/conversation_entity.dart';
import '../providers/inbox_providers.dart';
import '../utils/inbox_date_format.dart';
import '../utils/open_chat_detail.dart';
import 'smart_indicator_chip.dart';

/// Configures the shared [NmChatCard] from a [ConversationEntity] and adds
/// everything specific to the Inbox: swipe actions (`flutter_slidable`),
/// a long-press options sheet, a Hero'd avatar, and the tap targets that
/// route to Chat Detail vs. Profile Detail.
class ConversationCard extends ConsumerWidget {
  final ConversationEntity conversation;

  const ConversationCard({super.key, required this.conversation});

  String _subtitleMeta(AppLocalizations l10n) {
    final profile = conversation.profile;
    final parts = <String>[
      if (profile.age > 0) '${profile.age}',
      if (profile.location.isNotEmpty) profile.location,
      if (profile.compatibility.overallCompatibility > 0)
        l10n.inboxCompatibilityLabel(profile.compatibility.overallCompatibility),
    ];
    return parts.join(' · ');
  }

  NmReadStatus _readStatus() {
    if (!conversation.lastMessageFromMe) return NmReadStatus.none;
    return switch (conversation.lastMessageStatus) {
      MessageDeliveryStatus.sent => NmReadStatus.sent,
      MessageDeliveryStatus.delivered => NmReadStatus.delivered,
      MessageDeliveryStatus.read => NmReadStatus.read,
      null => NmReadStatus.none,
    };
  }

  void _showOptionsSheet(BuildContext context, WidgetRef ref, AppLocalizations l10n) {
    final notifier = ref.read(conversationsNotifierProvider.notifier);
    AppSheets.showActionSheet(
      context,
      title: conversation.profile.name,
      actions: [
        AppSheetAction(
          icon: Icons.person_outline_rounded,
          label: l10n.inboxActionViewProfile,
          onTap: () => openProfileDetail(context, conversation.profile),
        ),
        AppSheetAction(
          icon: conversation.isMuted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
          label: conversation.isMuted ? l10n.inboxActionUnmute : l10n.inboxActionMute,
          onTap: () => notifier.mute(conversation.id, !conversation.isMuted),
        ),
        AppSheetAction(
          icon: conversation.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
          label: conversation.isArchived ? l10n.inboxActionUnarchive : l10n.inboxActionArchive,
          onTap: () => notifier.archive(conversation.id, !conversation.isArchived),
        ),
        AppSheetAction(
          icon: Icons.block_rounded,
          label: l10n.inboxActionBlock,
          isDestructive: true,
          onTap: () => notifier.block(conversation.id, true),
        ),
        AppSheetAction(
          icon: Icons.delete_outline_rounded,
          label: l10n.inboxActionDelete,
          isDestructive: true,
          onTap: () => notifier.delete(conversation.id),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(conversationsNotifierProvider.notifier);

    final card = NmChatCard(
      name: conversation.profile.name,
      lastMessage: conversation.lastMessage,
      time: formatConversationTime(conversation.lastMessageAt, l10n),
      unreadCount: conversation.unreadCount,
      isOnline: conversation.profile.isOnline,
      gender: conversation.profile.gender,
      avatarUrl: conversation.profile.photoUrls.isNotEmpty ? conversation.profile.photoUrls.first : null,
      subtitleMeta: _subtitleMeta(l10n),
      isVerified: conversation.profile.isVerified,
      isPremium: conversation.profile.isPremium,
      isPinned: conversation.isPinned,
      isMuted: conversation.isMuted,
      isTyping: conversation.isTyping,
      readStatus: _readStatus(),
      indicator: conversation.smartIndicator == ConversationSmartIndicator.none
          ? null
          : SmartIndicatorChip(indicator: conversation.smartIndicator),
      heroTag: 'conversation-avatar-${conversation.id}',
      onAvatarTap: () => openProfileDetail(context, conversation.profile),
      onTap: () {
        if (conversation.unreadCount > 0) notifier.markRead(conversation.id);
        openChatDetail(context, conversation);
      },
    );

    return Slidable(
      key: ValueKey(conversation.id),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.5,
        children: [
          SlidableAction(
            onPressed: (_) => notifier.pin(conversation.id, !conversation.isPinned),
            backgroundColor: AppColors.accentGold,
            foregroundColor: Colors.white,
            icon: Icons.push_pin_rounded,
            label: l10n.inboxActionPin,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
            padding: EdgeInsets.zero,
          ),
          SlidableAction(
            onPressed: (_) => notifier.markUnread(conversation.id),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            icon: Icons.mark_chat_unread_rounded,
            label: l10n.inboxActionMarkUnread,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.5,
        children: [
          SlidableAction(
            onPressed: (_) => notifier.archive(conversation.id, !conversation.isArchived),
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
            icon: Icons.archive_rounded,
            label: l10n.inboxActionArchive,
            padding: EdgeInsets.zero,
          ),
          SlidableAction(
            onPressed: (_) => notifier.delete(conversation.id),
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            icon: Icons.delete_rounded,
            label: l10n.inboxActionDelete,
            borderRadius: const BorderRadius.horizontal(right: Radius.circular(18)),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
      child: GestureDetector(
        onLongPress: () => _showOptionsSheet(context, ref, l10n),
        child: card,
      ),
    );
  }
}
