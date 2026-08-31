import 'dart:async';
import 'package:cross_file/cross_file.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/realtime/realtime_providers.dart';
import '../../../../core/realtime/realtime_service.dart';
import '../../../../core/router/profile_navigation.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/dialogs/app_dialogs.dart';
import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/conversation_entity.dart';
import '../../domain/entities/message_entity.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../controllers/typing_controller.dart';
import '../providers/inbox_providers.dart';
import '../providers/presence_providers.dart';
import '../utils/handle_unblock_conversation.dart';
import '../widgets/chat_composer.dart';
import '../widgets/chat_presence.dart';
import '../widgets/date_separator.dart';
import '../widgets/message_bubble.dart';
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

class _ChatDetailPageState extends ConsumerState<ChatDetailPage>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();

  // How close to the bottom counts as "already there" for auto-scroll
  // purposes, and how close to the top triggers loading older history —
  // both in logical pixels.
  static const _bottomThreshold = 120.0;
  static const _topThreshold = 200.0;

  bool _isNearBottom = true;
  int _unseenNewMessages = 0;
  bool _isLoadingOlder = false;

  /// Set the first time this thread's messages resolve (page 1 landing) —
  /// gates the one-time no-animation jump to the newest message so it never
  /// re-fires on a later page/prepend/new-message update.
  bool _hasScrolledToInitialMessage = false;

  /// In-flight/pending guards for [_markThreadRead] — coalesces every
  /// trigger that lands while a call is already in flight (initial open
  /// racing a burst of incoming messages) into exactly one trailing retry,
  /// never one request per trigger.
  bool _markReadInFlight = false;
  bool _markReadPending = false;

  /// The message currently being replied to (long-press → Reply), or null.
  /// Rendered as a preview banner above [ChatComposer]'s input row; cleared
  /// on send or via the banner's close button.
  MessageEntity? _replyTarget;

  /// The message currently flashing a highlight tint (tapped its own
  /// reply-quote elsewhere and just scrolled here) — cleared by
  /// [_highlightTimer] after a brief window.
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  /// GlobalKeys per loaded message id, shared with [_MessagesList] — lets
  /// [_scrollToMessage] locate an already-built row's [BuildContext] via
  /// [Scrollable.ensureVisible]. Reuses the same key across rebuilds (same
  /// Map instance handed down each build) and across a message's whole
  /// lifetime in this session; entries are never evicted, which is fine —
  /// a GlobalKey with no currently-built Element costs next to nothing.
  final Map<String, GlobalKey> _messageKeys = {};

  /// Debounces this client's outgoing typing signal (start once per burst, stop
  /// on idle / send / leaving) and forwards it to the repository's socket emit.
  /// The single state machine for typing — `ChatComposer` only forwards raw
  /// text/focus signals into it; no other timer anywhere decides start/stop.
  late final TypingController _typing;

  /// Discards `_typing`'s "already told the peer" assumption on every
  /// reconnect (see [TypingController.resetForReconnect]) — a `true` sent
  /// while disconnected never reached them.
  late final StreamSubscription<void> _readySubscription;

  /// Dependencies resolved once at mount and held directly, because
  /// [dispose] needs them.
  ///
  /// `ref` is only valid while this widget is alive: reading a provider from
  /// `dispose()` throws (`Cannot use "ref" after the widget was disposed`),
  /// and during app teardown or a ProviderScope rebuild the container may
  /// already be gone. Both teardown signals this screen owes the server —
  /// "stop suppressing pushes for this thread" and a final `typing_stop` —
  /// would be lost to that exception, leaving the peer stuck on a typing
  /// indicator and this member silently un-notified for the thread.
  ///
  /// Both providers are app-scoped singletons that outlive this page, so
  /// holding the instances is safe; it is the *lookup* that is not.
  late final RealtimeService _realtime;
  late final ConversationRepository _conversationRepository;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _realtime = ref.read(realtimeServiceProvider);
    _conversationRepository = ref.read(conversationRepositoryProvider);
    _typing = TypingController(
      // Deliberately the cached repository, not a ref.read: TypingController
      // .dispose() fires this callback one last time from inside our own
      // dispose().
      onTyping: (isTyping) =>
          _conversationRepository.setTyping(widget.conversation.id, isTyping),
    );
    _readySubscription = _realtime.onReady.listen(
      (_) => _typing.resetForReconnect(),
    );
    // Tell the server this thread is on screen so it suppresses chat pushes for
    // it — the member is watching messages arrive live, so a lock-screen buzz
    // for the same message is pure noise. RealtimeService remembers the id and
    // re-sends it on reconnect, so this single call covers the socket dropping.
    _realtime.setViewingConversation(widget.conversation.id);
    // Mark this thread read the moment it opens — a single, entry-point-
    // agnostic trigger (Inbox tap, Profile Detail's Message button, or any
    // future deep link/push-notification route all land here) instead of
    // the old approach of the Inbox row's tap handler doing it. Deferred a
    // frame so it never runs during this widget's own mount/build.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_markThreadRead()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_readySubscription.cancel());
    // Leaving the screen must resume pushes for this thread. Cleared here — the
    // one exit every route out of the chat goes through — rather than in a back
    // handler, which a swipe-back or a deep link elsewhere would bypass. The
    // server also clears on disconnect and on background, so a crash cannot
    // leave this member silently un-notified.
    //
    // Cached instances only — see [_realtime]/[_conversationRepository]. No
    // ref.read/watch/invalidate may appear below this line.
    _realtime.setViewingConversation(null);
    _typing.dispose(); // emits a final typing_stop so the peer isn't left stuck
    _highlightTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Stops typing the moment this screen is backgrounded — mirrors
  /// `RealtimeService.handleAppBackgrounded`'s own choice to act only on
  /// `paused`/`detached` (not `inactive`/`hidden`, which are transient — app
  /// switcher, an incoming call overlay — and would otherwise flap the
  /// indicator for no reason). Conversation-closed is already covered by
  /// [dispose]; this handles staying on the same screen while the app itself
  /// loses focus.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _typing.stop();
        // No stopViewing emit needed: RealtimeService.handleAppBackgrounded
        // already sends `presence.offline`, and the server drops this device's
        // viewing registration as part of handling it. Backgrounded means the
        // member is not looking, so pushes must resume — which they do.
        break;
      case AppLifecycleState.resumed:
        // ...and re-register on the way back, since that same handler cleared
        // it server-side while we were away.
        _realtime.setViewingConversation(widget.conversation.id);
      default:
        break;
    }
  }

  /// Marks this thread's unread messages read. The single entry-point-
  /// agnostic trigger for read receipts — called from [initState] (opening
  /// the thread) and from the new-message branch in [build]'s
  /// `ref.listen` (a peer message landing while the thread is already
  /// open). Skips the network call entirely when the live conversation
  /// list already shows nothing unread for this room, and coalesces
  /// overlapping triggers via [_markReadInFlight]/[_markReadPending] so a
  /// fast burst of triggers never produces more than one request in
  /// flight plus a single trailing retry.
  Future<void> _markThreadRead() async {
    if (_markReadInFlight) {
      _markReadPending = true;
      return;
    }

    final conversationId = widget.conversation.id;
    final conversations = ref.read(conversationsNotifierProvider).valueOrNull;
    ConversationEntity? live;
    if (conversations != null) {
      for (final c in conversations) {
        if (c.id == conversationId) {
          live = c;
          break;
        }
      }
    }
    // The live list is the source of truth once it's loaded — if it already
    // shows nothing unread for this room, there's nothing to persist.
    if (live != null && live.unreadCount <= 0) return;

    _markReadInFlight = true;
    try {
      if (conversations != null) {
        // Normal case: the Inbox list is already loaded — go through the
        // notifier so its optimistic unreadCount update keeps the list and
        // its badge in sync, exactly like the old ConversationCard tap did.
        await ref
            .read(conversationsNotifierProvider.notifier)
            .markRead(conversationId);
      } else {
        // Cold-start / deep-link / push-notification case: this screen can
        // open before the conversations list has ever been fetched, and
        // `ConversationsNotifier`'s shared `_apply` helper no-ops (never
        // calls the repository) while its own state hasn't loaded yet. Call
        // the repository directly so the read receipt still fires — the
        // list picks up the already-server-side-read unreadCount the next
        // time it loads.
        await ref.read(conversationRepositoryProvider).markRead(conversationId);
      }
    } finally {
      _markReadInFlight = false;
      if (_markReadPending && mounted) {
        _markReadPending = false;
        unawaited(_markThreadRead());
      } else {
        _markReadPending = false;
      }
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// No-animation counterpart to [_scrollToBottom] — used only for the
  /// one-time initial jump to the newest message when a thread first opens,
  /// so the first frame the user sees is already at the bottom.
  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  /// Settles the initial jump against `ListView.builder`'s lazy extent
  /// estimate. At offset 0 (topmost/oldest message), `SliverChildBuilderDelegate`
  /// only knows the real size of whichever items are actually laid out near
  /// the top — `maxScrollExtent` for everything below that is an
  /// extrapolated estimate, not the true value. Jumping to that estimate
  /// makes Flutter build the newly-visible items around the new offset with
  /// their REAL heights, which can grow `maxScrollExtent` further (message
  /// bubbles vary in height — images, reply-quotes, multi-line text — so the
  /// estimate is rarely exact). Re-jumping to the updated extent after each
  /// frame and stopping only once a jump causes no further change converges
  /// on the true final bottom deterministically, without an arbitrary delay
  /// or offset. Every step is a `jumpTo` (never animated), and for a normal
  /// thread this converges within a couple of frames — well before the user
  /// perceives anything as a "scroll".
  Future<void> _settleInitialScrollToBottom() async {
    const maxAttempts = 8;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!mounted || !_scrollController.hasClients) return;
      final extent = _scrollController.position.maxScrollExtent;
      // ignore: avoid_print
      print('Before jump: ${_scrollController.position.maxScrollExtent}');
      _jumpToBottom();
      // ignore: avoid_print
      print('After jump: ${_scrollController.offset}');
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) return;
      final settled = _scrollController.position.maxScrollExtent;
      // ignore: avoid_print
      print(
        'After final layout: ${_scrollController.position.maxScrollExtent}',
      );
      if (settled == extent) {
        return; // stable: that jump caused no further growth
      }
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;

    final nearBottom =
        position.pixels >= position.maxScrollExtent - _bottomThreshold;
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
    final notifier = ref.read(
      messagesProvider(widget.conversation.id).notifier,
    );
    if (!notifier.hasMoreHistory) return;

    setState(() => _isLoadingOlder = true);
    // Prepending older messages grows maxScrollExtent — without correcting
    // `pixels` by exactly that growth, the currently-visible messages would
    // visually jump down the screen once the new (taller) content lays out.
    final oldExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
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

  /// Re-resolves [_replyTarget] against the current message list right
  /// before it's attached to an outgoing send — picks up a since-confirmed
  /// server id if the target was still `sending` at the moment "Reply" was
  /// chosen (matched by `clientMessageId` first, falling back to `id`, same
  /// dedup key [MessagesNotifier.applyIncoming] already uses). Falls back to
  /// the originally-captured snapshot if the target can't be found (e.g. it
  /// scrolled out of the currently-loaded page) — replying to it is still
  /// valid, this just couldn't refresh its preview text/type.
  MessageEntity? _resolveReplyTarget() {
    final target = _replyTarget;
    if (target == null) return null;
    final messages = ref
        .read(messagesProvider(widget.conversation.id))
        .valueOrNull;
    if (messages == null) return target;
    for (final m in messages) {
      if (m.id == target.id ||
          (target.clientMessageId != null &&
              m.clientMessageId == target.clientMessageId)) {
        return m;
      }
    }
    return target;
  }

  /// Tapping a bubble's own reply-quote calls this with the original
  /// message's id: loads older history automatically until the original is
  /// found (or there's nothing more to load), then scrolls to and briefly
  /// highlights it. A silent no-op if it can never be found — e.g. it's
  /// older than this conversation's retained history.
  Future<void> _scrollToMessage(String messageId) async {
    final conversationId = widget.conversation.id;
    final notifier = ref.read(messagesProvider(conversationId).notifier);

    bool isLoaded() =>
        (ref.read(messagesProvider(conversationId)).valueOrNull ?? const [])
            .any((m) => m.id == messageId);

    if (!isLoaded()) {
      // Reuses the same "loading older" spinner _onScroll's own pagination
      // already shows — this is just a second, programmatic trigger for the
      // identical [MessagesNotifier.loadOlder] pagination.
      if (mounted) setState(() => _isLoadingOlder = true);
      while (mounted && !isLoaded()) {
        if (!notifier.hasMoreHistory) break;
        await notifier.loadOlder();
      }
      if (mounted) setState(() => _isLoadingOlder = false);
    }
    if (!mounted || !isLoaded()) return;

    // The target is in the loaded list now, but ListView.builder is lazy —
    // its row may not be built yet. Nudge the scroll position toward its
    // estimated offset (average item extent × index) so the list builds it,
    // then fine-tune with Scrollable.ensureVisible once its GlobalKey
    // resolves a context — capped at a handful of attempts.
    for (var attempt = 0; attempt < 6; attempt++) {
      final targetContext = _messageKeys[messageId]?.currentContext;
      if (targetContext != null) {
        // Not a stale BuildContext from before the `await`s above — this is
        // the target row's OWN element context, fetched fresh this same
        // synchronous tick and null-checked right here, not `this.context`.
        await Scrollable.ensureVisible(
          targetContext, // ignore: use_build_context_synchronously
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.5,
        );
        if (mounted) _highlightMessage(messageId);
        return;
      }
      if (!_scrollController.hasClients) return;
      final messages = ref.read(messagesProvider(conversationId)).valueOrNull;
      if (messages == null) return;
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index == -1) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final estimatedOffset = (index * (maxExtent / messages.length)).clamp(
        0.0,
        maxExtent,
      );
      _scrollController.jumpTo(estimatedOffset);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
    }
  }

  void _highlightMessage(String messageId) {
    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    final messagesNotifier = ref.read(
      messagesProvider(conversation.id).notifier,
    );

    // `messagesProvider` is a plain (non-autoDispose) family provider — once
    // any conversation has been opened, its message list stays resolved for
    // the rest of the app session. Watching the CURRENT value here (rather
    // than only reacting to a loading→data transition below) is what makes
    // the initial jump-to-bottom fire on every open: a first-ever open still
    // catches the transition on a later rebuild once the fetch resolves, and
    // a reopen of an already-loaded conversation sees data immediately, on
    // this very build, with no transition ever occurring for `ref.listen` to
    // observe.
    final currentMessages = ref
        .watch(messagesProvider(conversation.id))
        .valueOrNull;
    if (!_hasScrolledToInitialMessage &&
        currentMessages != null &&
        currentMessages.isNotEmpty) {
      _hasScrolledToInitialMessage = true;
      // No animation: settles to the newest message once layout is actually
      // stable (see `_settleInitialScrollToBottom`) — the earliest point the
      // TRUE `maxScrollExtent` is known without switching the list to
      // `reverse: true`.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_settleInitialScrollToBottom());
      });
    }

    ref.listen(messagesProvider(conversation.id), (previous, next) {
      final prevMessages = previous?.valueOrNull;
      final nextMessages = next.valueOrNull;
      if (nextMessages == null) return;

      // No previous data at all means this is the thread's very first
      // resolution — already handled by the eager check above (which covers
      // both an already-cached provider and one resolving for the first
      // time), so it must never also be treated as "a new message arrived".
      if (prevMessages == null) return;

      final prevLen = prevMessages.length;
      if (nextMessages.length <= prevLen) return;

      // A load-older prepend also grows the list — distinguish it from a
      // genuinely new message by checking whether the *tail* changed. Only
      // a changed tail should ever trigger auto-scroll or the unseen-count.
      final tailUnchanged =
          prevMessages.isNotEmpty &&
          nextMessages.last.id == prevMessages.last.id;
      if (tailUnchanged) return;

      final newest = nextMessages.last;
      if (newest.isMine || _isNearBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      } else {
        setState(() => _unseenNewMessages++);
      }
      // A genuinely new message from the peer, landing while this thread is
      // already open — mark it (and anything else unread in the room) read
      // immediately instead of waiting for the user to leave and reopen.
      if (!newest.isMine) {
        unawaited(_markThreadRead());
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
                        peerUserId: conversation.profile.id,
                        peerName: conversation.profile.name,
                        scrollController: _scrollController,
                        isLoadingOlder: _isLoadingOlder,
                        onRetry: (clientMessageId) =>
                            messagesNotifier.retry(clientMessageId),
                        onReply: (message) =>
                            setState(() => _replyTarget = message),
                        onTapReplyPreview: (messageId) =>
                            unawaited(_scrollToMessage(messageId)),
                        messageKeys: _messageKeys,
                        highlightedMessageId: _highlightedMessageId,
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
                    onSend: (text) {
                      final replyTo = _resolveReplyTarget();
                      // No explicit `_typing.stop()` needed here — ChatComposer's
                      // own _submit() already forwards the now-empty text before
                      // calling this, which stops typing via the same single
                      // path as clearing the field manually would.
                      messagesNotifier.send(text, replyTo: replyTo);
                      if (_replyTarget != null) {
                        setState(() => _replyTarget = null);
                      }
                    },
                    onSendAttachment: (XFile file) {
                      final replyTo = _resolveReplyTarget();
                      if (_replyTarget != null) {
                        setState(() => _replyTarget = null);
                      }
                      return messagesNotifier.sendImage(file, replyTo: replyTo);
                    },
                    onSendVoice: (path, duration) {
                      final replyTo = _resolveReplyTarget();
                      if (_replyTarget != null) {
                        setState(() => _replyTarget = null);
                      }
                      return messagesNotifier.sendVoice(
                        path,
                        duration,
                        replyTo: replyTo,
                      );
                    },
                    // ChatComposer forwards raw text on every change (and on
                    // focus loss); _typing.onChanged is the ONE place that
                    // debounces it into a single typing_start + an idle stop.
                    onTypingTextChanged: _typing.onChanged,
                    replyTarget: _replyTarget,
                    peerName: conversation.profile.name,
                    onClearReply: () => setState(() => _replyTarget = null),
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
              const Icon(
                Icons.arrow_downward_rounded,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                '${l10n.inboxNewMessages} ($count)',
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
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
        onTap: () => openProfileDetail(
          context,
          profile,
          isBlocked: conversation.isBlocked,
        ),
        child: Row(
          children: [
            Hero(
              tag: 'conversation-avatar-${conversation.id}',
              child: PresenceAvatar(
                userId: profile.id,
                imageUrl: profile.photoUrls.isNotEmpty
                    ? profile.photoUrls.first
                    : null,
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
                  ChatPresenceSubtitle(
                    userId: profile.id,
                    onlineLabel: l10n.inboxOnline,
                    locale: Localizations.localeOf(context).toString(),
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
                onTap: () => openProfileDetail(
                  context,
                  profile,
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
                onTap: () => ref
                    .read(conversationsNotifierProvider.notifier)
                    .mute(conversation.id, !conversation.isMuted),
              ),
              AppSheetAction(
                icon: conversation.isBlocked
                    ? Icons.lock_open_rounded
                    : Icons.block_rounded,
                label: conversation.isBlocked
                    ? l10n.inboxActionUnblock
                    : l10n.inboxActionBlock,
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
      ref
          .read(conversationsNotifierProvider.notifier)
          .block(conversation.id, true);
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _MessagesList extends ConsumerWidget {
  final String conversationId;
  final String peerUserId;
  final String peerName;
  final ScrollController scrollController;
  final bool isLoadingOlder;
  final ValueChanged<String> onRetry;

  /// Long-press → "Reply" chosen for a message — bubbles up to
  /// `ChatDetailPage` so it can drive the composer's reply-preview banner.
  final ValueChanged<MessageEntity> onReply;

  /// Tapping a message's own reply-quote — bubbles up to
  /// `ChatDetailPage._scrollToMessage`.
  final ValueChanged<String> onTapReplyPreview;

  /// Shared with `ChatDetailPage` (same Map instance every build) so
  /// `_scrollToMessage` can look up an already-built row's context.
  final Map<String, GlobalKey> messageKeys;

  final String? highlightedMessageId;

  const _MessagesList({
    required this.conversationId,
    required this.peerUserId,
    required this.peerName,
    required this.scrollController,
    required this.isLoadingOlder,
    required this.onRetry,
    required this.onReply,
    required this.onTapReplyPreview,
    required this.messageKeys,
    required this.highlightedMessageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messagesAsync = ref.watch(messagesProvider(conversationId));
    // Live typing for the in-thread indicator — narrow watch so only this list
    // rebuilds when the peer starts/stops typing (never the whole page).
    final isTyping = ref.watch(
      presenceProvider.select((m) => m[peerUserId]?.isTyping ?? false),
    );

    return messagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text(AppLocalizations.of(context).inboxLoadError)),
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
          scrollCacheExtent: const ScrollCacheExtent.pixels(800),
          itemCount: leadingCount + messages.length + trailingCount,
          itemBuilder: (context, index) {
            if (isLoadingOlder && index == 0) {
              return const Padding(
                key: ValueKey('loading-older'),
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
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
            final showDateSeparator =
                messageIndex == 0 ||
                !_isSameDay(messages[messageIndex - 1].sentAt, message.sentAt);
            // Long-press opens Reply/Edit/Delete for any message — EXCEPT a
            // failed send, whose whole bubble already handles tap-to-retry
            // (see message_bubble.dart's `canRetry`) and must not compete
            // with a long-press gesture for the same bubble.
            final canLongPress = message.status != MessageStatus.failed;
            return Column(
              key: messageKeys.putIfAbsent(message.id, GlobalKey.new),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showDateSeparator) DateSeparator(date: message.sentAt),
                MessageBubble(
                  message: message,
                  onRetry: message.status == MessageStatus.failed
                      ? onRetry
                      : null,
                  onLongPress: canLongPress
                      ? () => _showMessageActions(context, ref, message)
                      : null,
                  peerName: peerName,
                  isHighlighted: highlightedMessageId == message.id,
                  onTapReplyPreview: onTapReplyPreview,
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

  /// Long-press actions: Reply is offered for any message (own or the
  /// peer's, sent/delivered/read/edited/deleted/still-sending — see
  /// `ChatDetailPage`'s doc comments on why each of those is safe to reply
  /// to). Edit/Delete are sender-only and only shown for this user's own,
  /// non-deleted messages; the server re-enforces every rule regardless — a
  /// rejected edit/delete just reverts.
  Future<void> _showMessageActions(
    BuildContext context,
    WidgetRef ref,
    MessageEntity message,
  ) async {
    final notifier = ref.read(messagesProvider(conversationId).notifier);
    // Hide Edit outright once the backend's edit window has passed, or while
    // an edit for this message is already saving — Delete stays available
    // either way (it has no time window and isn't subject to the same race).
    final canEdit =
        message.isMine &&
        !message.isDeleted &&
        message.type == MessageType.text &&
        !isMessageEditWindowExpired(message.sentAt) &&
        !notifier.isEditPending(message.id);
    final canDelete = message.isMine && !message.isDeleted;
    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_outlined),
              title: Text(AppLocalizations.of(context).commonReply),
              onTap: () => Navigator.of(sheetContext).pop(_MessageAction.reply),
            ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(
                  AppLocalizations.of(context).registrationEditButton,
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_MessageAction.edit),
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: AppColors.error,
                ),
                title: Text(
                  AppLocalizations.of(context).inboxActionDelete,
                  style: const TextStyle(color: AppColors.error),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_MessageAction.delete),
              ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _MessageAction.reply:
        onReply(message);
      case _MessageAction.edit:
        final newText = await _promptEditText(context, message.text);
        if (newText == null || newText.isEmpty || !context.mounted) return;
        try {
          await notifier.edit(message.id, newText);
        } catch (error) {
          if (!context.mounted) return;
          final errorMessage = error is ApiException
              ? error.message
              : error is MessageEditWindowExpiredException
              ? error.message
              : AppLocalizations.of(context).inboxEditMessageError;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(errorMessage)));
        }
      case _MessageAction.delete:
        final confirmed = await _confirmDelete(context);
        if (confirmed) await notifier.deleteMessage(message.id);
    }
  }

  Future<String?> _promptEditText(BuildContext context, String initial) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _EditMessageDialog(initialText: initial),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext).inboxDeleteMessageTitle),
        content: Text(
          AppLocalizations.of(dialogContext).inboxDeleteMessageBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              AppLocalizations.of(dialogContext).inboxActionDelete,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Long-press action chosen for a message (see `_showMessageActions`).
enum _MessageAction { reply, edit, delete }

/// Edit-message dialog content. Owns its [TextEditingController] for exactly
/// its own widget lifetime, disposing it in [dispose] — which Flutter only
/// calls once this Element is actually unmounted (after the dialog route's
/// exit transition finishes), never while the [TextField] below is still
/// part of the tree. Disposing the controller from the caller right after
/// `showDialog` resolves (the previous implementation) was too early: a
/// `DialogRoute`'s returned Future completes on `Navigator.pop()`, before its
/// exit animation finishes, so the still-animating-out `TextField` would get
/// rebuilt against an already-disposed controller.
class _EditMessageDialog extends StatefulWidget {
  const _EditMessageDialog({required this.initialText});

  final String initialText;

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context).inboxEditMessageTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: null,
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context).commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(AppLocalizations.of(context).actionSave),
        ),
      ],
    );
  }
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
              decoration: const BoxDecoration(
                color: AppColors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_rounded,
                size: 48,
                color: AppColors.secondaryDark,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.inboxPremiumLockedName,
              style: AppTypography.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.inboxPremiumLockedMessage,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondaryLight,
              ),
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
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondaryLight,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                handleUnblockConversation(context, ref, conversation),
            child: Text(l10n.inboxActionUnblock),
          ),
        ],
      ),
    );
  }
}
