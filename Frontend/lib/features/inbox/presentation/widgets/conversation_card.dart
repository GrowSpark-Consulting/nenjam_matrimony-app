import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../../core/router/profile_navigation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/cards/chat_card.dart';
import '../../../../core/widgets/dialogs/app_dialogs.dart';
import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/conversation_entity.dart';
import '../providers/inbox_providers.dart';
import '../providers/presence_providers.dart';
import '../utils/handle_unblock_conversation.dart';
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
        l10n.inboxCompatibilityLabel(
          profile.compatibility.overallCompatibility,
        ),
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

  void _showOptionsSheet(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final notifier = ref.read(conversationsNotifierProvider.notifier);
    AppSheets.showActionSheet(
      context,
      title: conversation.profile.name,
      actions: [
        AppSheetAction(
          icon: Icons.person_outline_rounded,
          label: l10n.inboxActionViewProfile,
          onTap: () => openProfileDetail(
            context,
            conversation.profile,
            isBlocked: conversation.isBlocked,
          ),
        ),
        AppSheetAction(
          icon: conversation.isMuted
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          label: conversation.isMuted
              ? l10n.inboxActionUnmute
              : l10n.inboxActionMute,
          onTap: () => notifier.mute(conversation.id, !conversation.isMuted),
        ),
        AppSheetAction(
          icon: conversation.isArchived
              ? Icons.unarchive_outlined
              : Icons.archive_outlined,
          label: conversation.isArchived
              ? l10n.inboxActionUnarchive
              : l10n.inboxActionArchive,
          onTap: () =>
              notifier.archive(conversation.id, !conversation.isArchived),
        ),
        AppSheetAction(
          icon: conversation.isBlocked
              ? Icons.lock_open_rounded
              : Icons.block_rounded,
          label: conversation.isBlocked
              ? l10n.inboxActionUnblock
              : l10n.inboxActionBlock,
          isDestructive: !conversation.isBlocked,
          onTap: () => _confirmBlock(context, ref, l10n),
        ),
        AppSheetAction(
          icon: Icons.delete_outline_rounded,
          label: l10n.inboxActionDelete,
          isDestructive: true,
          onTap: () => _confirmDelete(context, notifier, l10n),
        ),
      ],
    );
  }

  Future<void> _confirmBlock(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    if (conversation.isBlocked) {
      await handleUnblockConversation(context, ref, conversation);
      return;
    }
    final confirmed = await AppDialogs.showConfirmation(
      context,
      title: l10n.inboxBlockConfirmTitle(conversation.profile.name),
      message: l10n.inboxBlockConfirmMessage,
      confirmLabel: l10n.inboxActionBlock,
    );
    if (confirmed ?? false) {
      ref
          .read(conversationsNotifierProvider.notifier)
          .block(conversation.id, true);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ConversationsNotifier notifier,
    AppLocalizations l10n,
  ) async {
    final confirmed = await AppDialogs.showDelete(
      context,
      title: l10n.inboxDeleteConfirmTitle,
      message: l10n.inboxDeleteConfirmMessage,
    );
    if (confirmed ?? false) notifier.delete(conversation.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(conversationsNotifierProvider.notifier);

    // Live presence for this peer only — a narrow `select` so just this row
    // rebuilds (and only when its peer's online/typing flips), never the list.
    final presence = ref.watch(
      presenceProvider.select((m) => m[conversation.profile.id]),
    );
    final isOnline = presence?.isOnline ?? conversation.isOnline;
    final isTyping = presence?.isTyping ?? conversation.isTyping;

    final card = NmChatCard(
      name: conversation.profile.name,
      lastMessage: conversation.lastMessage,
      time: formatConversationTime(conversation.lastMessageAt, l10n),
      unreadCount: conversation.unreadCount,
      isOnline: isOnline,
      gender: conversation.profile.gender,
      avatarUrl: conversation.profile.photoUrls.isNotEmpty
          ? conversation.profile.photoUrls.first
          : null,
      subtitleMeta: _subtitleMeta(l10n),
      isVerified: conversation.profile.isVerified,
      isPremium: conversation.profile.isPremium,
      isPinned: conversation.isPinned,
      isMuted: conversation.isMuted,
      isTyping: isTyping,
      readStatus: _readStatus(),
      indicator: conversation.smartIndicator == ConversationSmartIndicator.none
          ? null
          : SmartIndicatorChip(indicator: conversation.smartIndicator),
      heroTag: 'conversation-avatar-${conversation.id}',
      onAvatarTap: () => openProfileDetail(
        context,
        conversation.profile,
        isBlocked: conversation.isBlocked,
      ),
      // Marking read now happens in ChatDetailPage's own lifecycle (entry-
      // point-agnostic — also covers Profile Detail's Message button and any
      // future deep link/push route), not here, so it can't double-fire.
      onTap: () => openChatDetail(context, conversation),
    );

    return Slidable(
      key: ValueKey(conversation.id),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.5,
        children: [
          SlidableAction(
            onPressed: (_) =>
                notifier.pin(conversation.id, !conversation.isPinned),
            backgroundColor: AppColors.secondary,
            foregroundColor: Colors.white,
            icon: Icons.push_pin_rounded,
            label: l10n.inboxActionPin,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(18),
            ),
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
            onPressed: (_) =>
                notifier.archive(conversation.id, !conversation.isArchived),
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
            icon: Icons.archive_rounded,
            label: l10n.inboxActionArchive,
            padding: EdgeInsets.zero,
          ),
          SlidableAction(
            onPressed: (actionContext) =>
                _confirmDelete(actionContext, notifier, l10n),
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            icon: Icons.delete_rounded,
            label: l10n.inboxActionDelete,
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(18),
            ),
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
