import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/profile_navigation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatars/app_avatars.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/dialogs/app_dialogs.dart';
import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../providers/inbox_providers.dart';
import '../utils/handle_unblock_conversation.dart';
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

  // How close to the bottom counts as "already there" for auto-scroll
  // purposes, and how close to the top triggers loading older history —
  // both in logical pixels.
  static const _bottomThreshold = 120.0;
  static const _topThreshold = 200.0;

  bool _isNearBottom = true;
  int _unseenNewMessages = 0;
  bool _isLoadingOlder = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;

    final nearBottom = position.pixels >= position.maxScrollExtent - _bottomThreshold;
    if (nearBottom != _isNearBottom || (nearBottom && _unseenNewMessages > 0)) {
      setState(() {
        _isNearBottom = nearBottom;
        if (nearBottom) _unseenNewMessages = 0;
      });
    }

    if (position.pixels <= _topThreshold) _loadOlder();
  }

  Future<void> _loadOlder() async {
    if (_isLoadingOlder) return;
    final notifier = ref.read(messagesProvider(widget.conversation.id).notifier);
    if (!notifier.hasMoreHistory) return;

    setState(() => _isLoadingOlder = true);
    // Prepending older messages grows maxScrollExtent — without correcting
    // `pixels` by exactly that growth, the currently-visible messages would
    // visually jump down the screen once the new (taller) content lays out.
    final oldExtent = _scrollController.hasClients ? _scrollController.position.maxScrollExtent : 0.0;
    await notifier.loadOlder();
    if (!mounted) return;
    setState(() => _isLoadingOlder = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final delta = _scrollController.position.maxScrollExtent - oldExtent;
      if (delta > 0) {
        _scrollController.jumpTo(_scrollController.position.pixels + delta);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    final messagesNotifier = ref.read(messagesProvider(conversation.id).notifier);

    ref.listen(messagesProvider(conversation.id), (previous, next) {
      final prevMessages = previous?.valueOrNull;
      final nextMessages = next.valueOrNull;
      if (nextMessages == null) return;
      final prevLen = prevMessages?.length ?? -1;
      if (nextMessages.length <= prevLen) return;

      // A load-older prepend also grows the list — distinguish it from a
      // genuinely new message by checking whether the *tail* changed. Only
      // a changed tail should ever trigger auto-scroll or the unseen-count.
      final tailUnchanged = prevMessages != null &&
          prevMessages.isNotEmpty &&
          nextMessages.last.id == prevMessages.last.id;
      if (tailUnchanged) return;

      final newest = nextMessages.last;
      if (newest.isMine || _isNearBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      } else {
        setState(() => _unseenNewMessages++);
      }
    });

    return Scaffold(
      appBar: _ChatDetailAppBar(conversation: conversation),
      body: conversation.isLocked
          ? _LockedThread(conversation: conversation)
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      _MessagesList(
                        conversationId: conversation.id,
                        isTyping: conversation.isTyping,
                        scrollController: _scrollController,
                        isLoadingOlder: _isLoadingOlder,
                        onRetry: (clientMessageId) => messagesNotifier.retry(clientMessageId),
                      ),
                      if (_unseenNewMessages > 0)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _NewMessagesPill(
                              count: _unseenNewMessages,
                              onTap: () {
                                setState(() => _unseenNewMessages = 0);
                                _scrollToBottom();
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (conversation.isBlocked)
                  _BlockedBanner(conversation: conversation)
                else
                  ChatComposer(
                    onSend: (text) => messagesNotifier.send(text),
                    onSendAttachment: (File file) => messagesNotifier.sendImage(file.path),
                    onSendVoice: (path, duration) => messagesNotifier.sendVoice(path, duration),
                    onTypingChanged: (isTyping) => ref
                        .read(conversationRepositoryProvider)
                        .setTyping(conversation.id, isTyping),
                  ),
              ],
            ),
    );
  }
}

class _NewMessagesPill extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _NewMessagesPill({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_downward_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                '${l10n.inboxNewMessages} ($count)',
                style: AppTypography.labelMedium.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
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
        onTap: () => openProfileDetail(context, profile, isBlocked: conversation.isBlocked),
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
                onTap: () => openProfileDetail(context, profile, isBlocked: conversation.isBlocked),
              ),
              AppSheetAction(
                icon: conversation.isMuted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                label: conversation.isMuted ? l10n.inboxActionUnmute : l10n.inboxActionMute,
                onTap: () => ref
                    .read(conversationsNotifierProvider.notifier)
                    .mute(conversation.id, !conversation.isMuted),
              ),
              AppSheetAction(
                icon: conversation.isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                label: conversation.isBlocked ? l10n.inboxActionUnblock : l10n.inboxActionBlock,
                isDestructive: !conversation.isBlocked,
                onTap: () => _confirmBlock(context, ref, conversation, l10n),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmBlock(
    BuildContext context,
    WidgetRef ref,
    ConversationEntity conversation,
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
      ref.read(conversationsNotifierProvider.notifier).block(conversation.id, true);
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _MessagesList extends ConsumerWidget {
  final String conversationId;
  final bool isTyping;
  final ScrollController scrollController;
  final bool isLoadingOlder;
  final ValueChanged<String> onRetry;

  const _MessagesList({
    required this.conversationId,
    required this.isTyping,
    required this.scrollController,
    required this.isLoadingOlder,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messagesAsync = ref.watch(messagesProvider(conversationId));

    return messagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text(AppLocalizations.of(context).inboxLoadError)),
      data: (messages) {
        // itemCount layout: [0] older-history spinner (optional) ... [n]
        // messages ... [last] typing indicator (optional).
        final leadingCount = isLoadingOlder ? 1 : 0;
        final trailingCount = isTyping ? 1 : 0;

        return ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          // A bubble is small, but a long-running thread can still get deep
          // — a wider cache extent keeps fast flings from ever showing an
          // unbuilt gap.
          cacheExtent: 800,
          itemCount: leadingCount + messages.length + trailingCount,
          itemBuilder: (context, index) {
            if (isLoadingOlder && index == 0) {
              return const Padding(
                key: ValueKey('loading-older'),
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              );
            }
            final messageIndex = index - leadingCount;
            if (messageIndex == messages.length) {
              return const Padding(
                key: ValueKey('typing-indicator'),
                padding: EdgeInsets.only(top: 4),
                child: TypingIndicator(),
              );
            }
            final message = messages[messageIndex];
            final showDateSeparator = messageIndex == 0 ||
                !_isSameDay(messages[messageIndex - 1].sentAt, message.sentAt);
            // A confirmed message of this user's own can be edited/deleted via
            // long-press (the server still enforces sender-only, text-only, and
            // the edit window — a rejected edit just reverts).
            final canManage = message.isMine &&
                !message.isDeleted &&
                message.status != MessageStatus.sending &&
                message.status != MessageStatus.failed;
            return Column(
              key: ValueKey(message.id),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDateSeparator) DateSeparator(date: message.sentAt),
                MessageBubble(
                  message: message,
                  onRetry: message.status == MessageStatus.failed ? onRetry : null,
                  onLongPress:
                      canManage ? () => _showMessageActions(context, ref, message) : null,
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Long-press actions for this user's own message: edit (text only) or delete
  /// for everyone. The server re-enforces every rule; a rejected action reverts.
  Future<void> _showMessageActions(
    BuildContext context,
    WidgetRef ref,
    MessageEntity message,
  ) async {
    final notifier = ref.read(messagesProvider(conversationId).notifier);
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.type == MessageType.text)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.of(sheetContext).pop(_MessageAction.edit),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('Delete', style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.of(sheetContext).pop(_MessageAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _MessageAction.edit:
        final newText = await _promptEditText(context, message.text);
        if (newText != null && newText.isNotEmpty) {
          await notifier.edit(message.id, newText);
        }
      case _MessageAction.delete:
        final confirmed = await _confirmDelete(context);
        if (confirmed) await notifier.deleteMessage(message.id);
    }
  }

  Future<String?> _promptEditText(BuildContext context, String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be deleted for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Long-press action chosen for a message (see `_showMessageActions`).
enum _MessageAction { edit, delete }

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
            onPressed: () => handleUnblockConversation(context, ref, conversation),
            child: Text(l10n.inboxActionUnblock),
          ),
        ],
      ),
    );
  }
}
