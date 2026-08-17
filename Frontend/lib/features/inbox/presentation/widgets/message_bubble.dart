import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/message_entity.dart';
import 'chat_image_viewer_page.dart';
import 'chat_media_image.dart';
import '../../../../core/widgets/images/local_media_image.dart';

/// A single chat bubble — right-aligned/primary-filled for the current
/// user's own messages, left-aligned/surface-filled for the other person's,
/// with a small time + delivery-tick footer on outgoing messages.
///
/// Plays a brief fade + rise-in the first time it's built (new message
/// arriving) — [RepaintBoundary]'d so that animation, and any bubble's own
/// rebuild, never forces its neighbors to repaint.
class MessageBubble extends StatefulWidget {
  final MessageEntity message;

  /// Called when the user taps a [MessageStatus.failed] bubble to resend
  /// it. Null (the default) hides that affordance — Chat Detail always
  /// supplies it via [MessagesNotifier.retry].
  final ValueChanged<String>? onRetry;

  /// Called when the user long-presses this message — Chat Detail opens the
  /// reply/edit/delete actions sheet (which one of those three is offered
  /// depends on the message, not on whether this callback exists at all —
  /// Reply is available for any message). Null hides the gesture entirely.
  final VoidCallback? onLongPress;

  /// The peer's display name — used to resolve "You" vs their name when
  /// rendering [message.replyTo]'s sender label.
  final String peerName;

  /// True for a brief window right after the user tapped this message's own
  /// reply-quote elsewhere (scrolled here via [onTapReplyPreview]) — flashes
  /// a tint so the target is easy to spot, then fades back on its own.
  final bool isHighlighted;

  /// Called with the original message's id when the user taps this
  /// message's own reply-quote block (only rendered when [message.replyTo]
  /// is set) — Chat Detail scrolls to and highlights that original.
  final ValueChanged<String>? onTapReplyPreview;

  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onLongPress,
    this.peerName = '',
    this.isHighlighted = false,
    this.onTapReplyPreview,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: _MessageBubbleContent(
            message: widget.message,
            onRetry: widget.onRetry,
            onLongPress: widget.onLongPress,
            peerName: widget.peerName,
            isHighlighted: widget.isHighlighted,
            onTapReplyPreview: widget.onTapReplyPreview,
          ),
        ),
      ),
    );
  }
}

class _MessageBubbleContent extends StatelessWidget {
  final MessageEntity message;
  final ValueChanged<String>? onRetry;
  final VoidCallback? onLongPress;
  final String peerName;
  final bool isHighlighted;
  final ValueChanged<String>? onTapReplyPreview;

  const _MessageBubbleContent({
    required this.message,
    this.onRetry,
    this.onLongPress,
    this.peerName = '',
    this.isHighlighted = false,
    this.onTapReplyPreview,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isDeleted) {
      // A deleted message keeps its own minimal tombstone rendering, but
      // must still be reply-able (per the reply feature's own edge cases) —
      // reuse the same long-press gesture the normal bubble uses below,
      // without touching how the tombstone itself looks.
      final deleted = _DeletedBubble(isMine: message.isMine);
      return onLongPress == null
          ? deleted
          : GestureDetector(onLongPress: onLongPress, child: deleted);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final isMine = message.isMine;
    final canRetry = message.status == MessageStatus.failed &&
        message.clientMessageId != null &&
        onRetry != null;

    final bubbleColor = isMine
        ? AppColors.primary
        : (isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight);
    final textColor = isMine
        ? Colors.white
        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight);

    final bubble = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: EdgeInsets.fromLTRB(
        message.type == MessageType.image ? 6 : 14,
        message.type == MessageType.image ? 6 : 10,
        message.type == MessageType.image ? 6 : 14,
        10,
      ),
      decoration: BoxDecoration(
        // A brief tint flash when this bubble is the target of a tapped
        // reply-quote elsewhere — fades in/out via AnimatedContainer as
        // ChatDetailPage flips isHighlighted, no separate AnimationController
        // needed.
        color: isHighlighted
            ? Color.alphaBlend(AppColors.accentGoldLight.withValues(alpha: 0.4), bubbleColor)
            : bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMine ? 16 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.replyTo != null)
            _ReplyQuote(
              replyTo: message.replyTo!,
              peerName: peerName,
              isMine: isMine,
              onTap: onTapReplyPreview == null
                  ? null
                  : () => onTapReplyPreview!(message.replyTo!.id),
            ),
          if (message.type == MessageType.image && message.attachmentUrl != null)
            _MessageImage(
              url: message.attachmentUrl!,
              sending: message.status == MessageStatus.sending,
              conversationId: message.conversationId,
              messageId: message.id,
              // A failed image's whole bubble already handles tap-to-retry
              // (see `interactive` below) — the viewer's own tap must not
              // compete with that gesture for the same tap.
              viewerEnabled: !canRetry,
            )
          else if (message.type == MessageType.voice && message.attachmentUrl != null)
            _VoiceBubblePlayer(
              url: message.attachmentUrl!,
              knownDuration: message.voiceDuration,
              color: textColor,
              sending: message.status == MessageStatus.sending,
            )
          else
            Text(message.text, style: AppTypography.chatMessages.copyWith(color: textColor)),
          Padding(
            padding: EdgeInsets.only(
              top: 4,
              right: message.type == MessageType.image ? 6 : 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.editedAt != null) ...[
                  Text(
                    AppLocalizations.of(context).inboxMessageEdited,
                    style: AppTypography.labelSmall.copyWith(
                      color: textColor.withValues(alpha: 0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  _time(message.sentAt),
                  style: AppTypography.labelSmall.copyWith(
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  Icon(_statusIcon(), size: 13, color: _statusColor(textColor)),
                ],
              ],
            ),
          ),
          if (message.status == MessageStatus.failed) ...[
            const SizedBox(height: 2),
            Text(
              canRetry ? l10n.inboxRetrySend : l10n.inboxMessageFailed,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.error,
                decoration: canRetry ? TextDecoration.underline : null,
              ),
            ),
          ],
        ],
      ),
    );

    Widget interactive = bubble;
    if (canRetry) {
      interactive = InkWell(
        onTap: () => onRetry!(message.clientMessageId!),
        borderRadius: BorderRadius.circular(16),
        child: bubble,
      );
    } else if (onLongPress != null) {
      interactive = GestureDetector(onLongPress: onLongPress, child: bubble);
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: interactive,
    );
  }

  String _time(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  IconData _statusIcon() => switch (message.status) {
        MessageStatus.sending => Icons.schedule_rounded,
        MessageStatus.sent => Icons.check_rounded,
        MessageStatus.delivered => Icons.done_all_rounded,
        MessageStatus.read => Icons.done_all_rounded,
        MessageStatus.failed => Icons.error_outline_rounded,
      };

  Color _statusColor(Color textColor) =>
      message.status == MessageStatus.read ? AppColors.accentGoldLight : textColor.withValues(alpha: 0.7);
}

/// The quoted-reply block shown inside a bubble that replies to another
/// message — sender name, a one-line preview (text, or a type label for
/// media/deleted/edited, matching [conversationPreview]'s inbox-list
/// labels), and a thumbnail for an image reply. Tapping it (via [onTap])
/// scrolls to and highlights the original — see `ChatDetailPage._scrollToMessage`.
class _ReplyQuote extends StatelessWidget {
  final MessageReplyPreview replyTo;
  final String peerName;
  final bool isMine;
  final VoidCallback? onTap;

  const _ReplyQuote({
    required this.replyTo,
    required this.peerName,
    required this.isMine,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final senderLabel = replyTo.isMine ? 'You' : peerName;
    // Own bubble is primary-filled, so a plain white-on-white tint would be
    // invisible — use black-on-white there and the accent color on the
    // (lighter) peer bubble, same contrast rule the rest of this bubble
    // already follows via `isMine`.
    final barColor = isMine ? Colors.white : AppColors.primary;
    final quote = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: (isMine ? Colors.white : AppColors.primary).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: barColor, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: barColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _previewLabel(AppLocalizations.of(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: isMine ? Colors.white.withValues(alpha: 0.85) : null,
                  ),
                ),
              ],
            ),
          ),
          if (!replyTo.isDeleted &&
              replyTo.type == MessageType.image &&
              replyTo.attachmentUrl != null) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 36,
                height: 36,
                child: replyTo.attachmentUrl!.startsWith('http')
                    ? Image.network(replyTo.attachmentUrl!, fit: BoxFit.cover)
                    : NmLocalMediaImage(
                        source: replyTo.attachmentUrl!,
                        // 36x36 thumbnail — decode to size, not full photo.
                        cacheWidth:
                            (36 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
    return onTap == null ? quote : GestureDetector(onTap: onTap, child: quote);
  }

  String _previewLabel(AppLocalizations l10n) {
    if (replyTo.isDeleted) return l10n.inboxMessageDeleted;
    final edited = replyTo.editedAt != null ? l10n.inboxEditedSuffix : '';
    return switch (replyTo.type) {
      MessageType.image => '📷 ${l10n.inboxPreviewPhoto}$edited',
      MessageType.voice => '🎤 ${l10n.inboxComposerVoice}$edited',
      MessageType.document => '📄 ${l10n.inboxPreviewDocument}$edited',
      MessageType.text => '${replyTo.text}$edited',
    };
  }
}

/// The tombstone shown in place of a message that was deleted for everyone —
/// keeps the sender-side alignment but strips content, status, and any
/// long-press actions.
class _DeletedBubble extends StatelessWidget {
  final bool isMine;

  const _DeletedBubble({required this.isMine});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;
    final bg = isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_rounded, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                AppLocalizations.of(context).inboxMessageDeleted,
                style: AppTypography.chatMessages.copyWith(
                  color: color,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An image message's thumbnail — [url] is either a real `http(s)` URL (a
/// received message, or one this client sent that's since been confirmed
/// with a hosted URL) or a local file path (an attachment still
/// `sending`/uploading). Shows a dimming overlay + spinner while `sending`.
///
/// Tapping opens [ChatImageViewerPage] fullscreen (pinch/double-tap zoom,
/// pan) via a plain `Navigator.push` — pushing a new route on top leaves
/// this screen's own state (scroll position, pagination, composer/keyboard)
/// completely untouched, it's just visually covered until popped. A [Hero]
/// keyed by [messageId] flies the thumbnail into the fullscreen image.
/// [viewerEnabled] is false for a failed send, whose whole bubble already
/// handles tap-to-retry — the viewer must not compete for that same tap.
class _MessageImage extends StatelessWidget {
  final String url;
  final bool sending;
  final String conversationId;
  final String messageId;
  final bool viewerEnabled;

  const _MessageImage({
    required this.url,
    required this.sending,
    required this.conversationId,
    required this.messageId,
    this.viewerEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final heroTag = 'chat-image-$messageId';
    final image = ChatMediaImage(
      conversationId: conversationId,
      messageId: messageId,
      url: url,
      fit: BoxFit.cover,
      buildRefreshing: (_) => const _MessageImageLoading(),
      buildError: (_) => const _MessageImageError(),
    );

    final thumbnail = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 160, minHeight: 160, maxHeight: 260),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(tag: heroTag, child: image),
            if (sending)
              Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (!viewerEnabled) return thumbnail;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatImageViewerPage(
            conversationId: conversationId,
            messageId: messageId,
            heroTag: heroTag,
          ),
        ),
      ),
      child: thumbnail,
    );
  }
}

/// Shown in place of the bubble's image while a just-detected expired
/// presigned URL is being refreshed — same container/background treatment
/// as [_MessageImageError] (just a spinner instead of the broken-image
/// icon) so there's no jarring visual swap, only a brief, familiar-looking
/// loading state until the fix lands.
class _MessageImageLoading extends StatelessWidget {
  const _MessageImageLoading();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceVariantLight,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _MessageImageError extends StatelessWidget {
  const _MessageImageError();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceVariantLight,
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: AppColors.textTertiaryLight),
      ),
    );
  }
}

/// A voice message bubble's play/pause + progress + duration row.
///
/// [url] is either a real `http(s)` URL (once uploaded/confirmed) or a
/// local file path (this client's own not-yet-uploaded recording).
/// [knownDuration] comes from
/// [MessageEntity.voiceDuration] when this client is the one that recorded
/// it; for anything else, duration is only known once
/// `onDurationChanged` fires after the first play — shown as `--:--` until
/// then, never faked.
///
/// Lazily creates its own [AudioPlayer] on first play so a long message
/// list doesn't instantiate one player per bubble up front; disposed with
/// this widget.
class _VoiceBubblePlayer extends StatefulWidget {
  final String url;
  final Duration? knownDuration;
  final Color color;
  final bool sending;

  const _VoiceBubblePlayer({
    required this.url,
    required this.knownDuration,
    required this.color,
    required this.sending,
  });

  @override
  State<_VoiceBubblePlayer> createState() => _VoiceBubblePlayerState();
}

class _VoiceBubblePlayerState extends State<_VoiceBubblePlayer> {
  AudioPlayer? _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _duration = widget.knownDuration;
  }

  @override
  void dispose() {
    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    unawaited(_stateSub?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  void _ensurePlayer() {
    if (_player != null) return;
    final player = AudioPlayer();
    _positionSub = player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _durationSub = player.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _duration = duration);
    });
    _stateSub = player.onPlayerStateChanged.listen((playerState) {
      if (!mounted) return;
      setState(() {
        _isPlaying = playerState == PlayerState.playing;
        if (playerState == PlayerState.completed) _position = Duration.zero;
      });
    });
    _player = player;
  }

  Future<void> _togglePlay() async {
    if (widget.sending) return;
    _ensurePlayer();
    final player = _player!;
    if (_isPlaying) {
      await player.pause();
      return;
    }
    final source =
        widget.url.startsWith('http') ? UrlSource(widget.url) : DeviceFileSource(widget.url);
    await player.play(source);
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration;
    final progress = total == null || total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final displayed = _isPlaying || _position > Duration.zero ? _position : total;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          visualDensity: VisualDensity.compact,
          tooltip: _isPlaying ? 'Pause' : 'Play',
          onPressed: widget.sending ? null : _togglePlay,
          icon: Icon(
            _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
            color: widget.color,
            size: 30,
          ),
        ),
        SizedBox(
          width: 100,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              backgroundColor: widget.color.withValues(alpha: 0.25),
              color: widget.color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          displayed == null ? '--:--' : _formatVoiceDuration(displayed),
          style: AppTypography.labelSmall.copyWith(color: widget.color),
        ),
      ],
    );
  }
}

String _formatVoiceDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
