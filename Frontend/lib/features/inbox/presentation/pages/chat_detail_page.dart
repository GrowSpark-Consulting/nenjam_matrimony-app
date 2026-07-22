import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/profile_navigation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatars/app_avatars.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/conversation_entity.dart';
import '../providers/inbox_providers.dart';
import '../widgets/chat_composer.dart';
import '../widgets/date_separator.dart';
import '../widgets/message_bubble.dart';
import '../widgets/online_indicator.dart';
import '../widgets/typing_indicator.dart';

/// Production-quality Chat Detail thread — header, message history (with
/// date separators, delivery ticks, typing indicator), and a fully wired
/// text composer. Send/receive is mocked behind [ConversationRepository]
/// exactly like the rest of this feature — only that implementation needs
/// to change once a real chat backend exists; this page, its providers, and
/// its models are already shaped for it.
class ChatDetailPage extends ConsumerStatefulWidget {
  final ConversationEntity conversation;

  const ChatDetailPage({super.key, required this.conversation});

  @override
  ConsumerState<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends ConsumerState<ChatDetailPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;

    ref.listen(messagesProvider(conversation.id), (previous, next) {
      final prevLen = previous?.valueOrNull?.length ?? -1;
      final nextLen = next.valueOrNull?.length ?? -1;
      if (nextLen > prevLen) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    });

    return Scaffold(
      appBar: _ChatDetailAppBar(conversation: conversation),
      body: conversation.isLocked
          ? _LockedThread(conversation: conversation)
          : Column(
              children: [
                Expanded(
                  child: _MessagesList(
                    conversationId: conversation.id,
                    isTyping: conversation.isTyping,
                    scrollController: _scrollController,
                  ),
                ),
                if (conversation.isBlocked)
                  _BlockedBanner(conversation: conversation)
                else
                  ChatComposer(
                    onSend: (text) =>
                        ref.read(messagesProvider(conversation.id).notifier).send(text),
                  ),
              ],
            ),
    );
  }
}

class _ChatDetailAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final ConversationEntity conversation;

  const _ChatDetailAppBar({required this.conversation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = conversation.profile;

    return AppBar(
      titleSpacing: 0,
      title: InkWell(
        onTap: () => openProfileDetail(context, profile),
        child: Row(
          children: [
            Hero(
              tag: 'conversation-avatar-${conversation.id}',
              child: NmOnlineAvatar(
                imageUrl: profile.photoUrls.isNotEmpty ? profile.photoUrls.first : null,
                isOnline: profile.isOnline,
                size: 40,
                gender: profile.gender,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: AppTypography.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  OnlineIndicator(
                    isOnline: profile.isOnline,
                    onlineLabel: l10n.inboxOnline,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: l10n.inboxMoreOptions,
          onPressed: () => AppSheets.showActionSheet(
            context,
            title: profile.name,
            actions: [
              AppSheetAction(
                icon: Icons.person_outline_rounded,
                label: l10n.inboxActionViewProfile,
                onTap: () => openProfileDetail(context, profile),
              ),
              AppSheetAction(
                icon: conversation.isMuted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                label: conversation.isMuted ? l10n.inboxActionUnmute : l10n.inboxActionMute,
                onTap: () => ref
                    .read(conversationsNotifierProvider.notifier)
                    .mute(conversation.id, !conversation.isMuted),
              ),
              AppSheetAction(
                icon: Icons.block_rounded,
                label: l10n.inboxActionBlock,
                isDestructive: true,
                onTap: () => ref
                    .read(conversationsNotifierProvider.notifier)
                    .block(conversation.id, !conversation.isBlocked),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _MessagesList extends ConsumerWidget {
  final String conversationId;
  final bool isTyping;
  final ScrollController scrollController;

  const _MessagesList({
    required this.conversationId,
    required this.isTyping,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messagesAsync = ref.watch(messagesProvider(conversationId));

    return messagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(AppLocalizations.of(context).inboxLoadError)),
      data: (messages) {
        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          // A bubble is small, but a long-running thread can still get deep
          // — a wider cache extent keeps fast flings from ever showing an
          // unbuilt gap.
          cacheExtent: 800,
          itemCount: messages.length + (isTyping ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == messages.length) {
              return const Padding(
                key: ValueKey('typing-indicator'),
                padding: EdgeInsets.only(top: 4),
                child: TypingIndicator(),
              );
            }
            final message = messages[index];
            final showDateSeparator = index == 0 ||
                !_isSameDay(messages[index - 1].sentAt, message.sentAt);
            return Column(
              key: ValueKey(message.id),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDateSeparator) DateSeparator(date: message.sentAt),
                MessageBubble(message: message),
              ],
            );
          },
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _LockedThread extends StatelessWidget {
  final ConversationEntity conversation;

  const _LockedThread({required this.conversation});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(color: AppColors.accentGoldSurface, shape: BoxShape.circle),
              child: const Icon(Icons.lock_rounded, size: 48, color: AppColors.accentGoldDark),
            ),
            const SizedBox(height: 24),
            Text(l10n.inboxPremiumLockedName, style: AppTypography.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              l10n.inboxPremiumLockedMessage,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondaryLight),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: NmPrimaryButton(
                label: l10n.inboxUpgradeCta,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedBanner extends ConsumerWidget {
  final ConversationEntity conversation;

  const _BlockedBanner({required this.conversation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.inboxBlockedBanner,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondaryLight),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(conversationsNotifierProvider.notifier).block(conversation.id, false),
            child: Text(l10n.inboxActionUnblock),
          ),
        ],
      ),
    );
  }
}
