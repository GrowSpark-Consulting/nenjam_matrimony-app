import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/media/attachment_picker.dart';
import '../../../../core/services/media/voice_recorder_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/tokens/app_touch_target.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/message_entity.dart';
import '../providers/inbox_providers.dart' show conversationPreview;
import '../../../../core/widgets/images/local_media_image.dart';

/// Message composer — the text field + send button are fully wired to
/// [MessagesNotifier.send]/`.sendImage`/`.sendVoice`; the attach button
/// opens the same camera/gallery picker `PhotoManagerSection` uses for
/// profile photos. The emoji button opens a real emoji keyboard (inserts
/// Unicode text at the cursor via [_controller] — same text-send path as
/// any other typed message, no separate message type). The mic button
/// records a real local voice note — see [VoiceRecorderService] — but
/// sending one always ends in [MessageStatus.failed] today because no chat
/// attachment-upload endpoint exists yet (see
/// docs/development/chat-backend-handoff.md).
class ChatComposer extends StatefulWidget {
  final ValueChanged<String> onSend;
  final Future<void> Function(XFile file) onSendAttachment;
  final Future<void> Function(String path, Duration duration) onSendVoice;

  /// Fires on every text-field change with the CURRENT raw content (empty
  /// string when cleared) — the sole signal this widget sends about typing
  /// activity. All debounce/idle/start/stop timing is `TypingController`'s
  /// job (the caller typically passes its `onChanged` method directly);
  /// this widget doesn't run any timer of its own for it. Optional so this
  /// widget doesn't require a live typing backend to work.
  final ValueChanged<String>? onTypingTextChanged;

  /// The message currently being replied to, or null. `ChatDetailPage` owns
  /// this (set from a long-press "Reply" choice, cleared on send or via
  /// [onClearReply]) — this widget only renders the preview banner and
  /// provides the close affordance; it never decides what's attached to an
  /// outgoing message itself (that's `ChatDetailPage`'s `onSend`/
  /// `onSendAttachment`/`onSendVoice` closures, which already know
  /// [replyTarget] from the same enclosing state).
  final MessageEntity? replyTarget;

  /// The peer's display name, for rendering "Replying to {name}" — the
  /// composer has no other way to know who's on the other end of the
  /// conversation.
  final String peerName;

  /// Closes the reply preview banner without sending anything.
  final VoidCallback? onClearReply;

  const ChatComposer({
    super.key,
    required this.onSend,
    required this.onSendAttachment,
    required this.onSendVoice,
    this.onTypingTextChanged,
    this.replyTarget,
    this.peerName = '',
    this.onClearReply,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _PendingVoice {
  const _PendingVoice({required this.path, required this.duration});
  final String path;
  final Duration duration;
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _attachmentPicker = AttachmentPicker();
  final _voiceRecorder = VoiceRecorderService();
  bool _hasText = false;
  bool _isFocused = false;
  bool _isSending = false;
  bool _showEmojiPicker = false;
  XFile? _pendingAttachment;

  bool _isRecording = false;
  DateTime? _recordingStartedAt;
  _PendingVoice? _pendingVoice;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
    _focusNode.addListener(() {
      final hasFocus = _focusNode.hasFocus;
      setState(() {
        _isFocused = hasFocus;
        // Keyboard taking focus is how switching emoji-picker -> keyboard
        // happens (tapping the text field while the picker is open).
        if (hasFocus) _showEmojiPicker = false;
      });
      // Losing focus (tapping away, switching to the emoji picker, another
      // route covering this screen) means the user isn't actively editing
      // anymore — stop typing regardless of what's still in the field.
      // Regaining focus alone does NOT resume it; only an actual text
      // change does (see _handleTextChanged).
      if (!hasFocus) widget.onTypingTextChanged?.call('');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    unawaited(_voiceRecorder.dispose());
    super.dispose();
  }

  void _handleTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
    // Forward the raw text on every change — TypingController owns all
    // debounce/idle/start/stop timing from here; this widget runs no timer
    // of its own for it.
    widget.onTypingTextChanged?.call(_controller.text);
  }

  Future<void> _submit() async {
    if (_isSending) return; // guards a rapid double-tap on Send

    final pendingVoice = _pendingVoice;
    if (pendingVoice != null) {
      setState(() {
        _isSending = true;
        _pendingVoice = null;
      });
      widget.onTypingTextChanged?.call('');
      await widget.onSendVoice(pendingVoice.path, pendingVoice.duration);
      if (mounted) setState(() => _isSending = false);
      return;
    }

    final attachment = _pendingAttachment;
    if (attachment != null) {
      setState(() {
        _isSending = true;
        _pendingAttachment = null;
      });
      widget.onTypingTextChanged?.call('');
      await widget.onSendAttachment(attachment);
      if (mounted) setState(() => _isSending = false);
      return;
    }

    final text = _controller.text;
    if (text.trim().isEmpty) return;
    // Clearing synchronously (before onSend even runs) is what makes a
    // rapid double-tap safe without an extra flag: the send button swaps
    // out for the mic icon (via _hasText) the instant this happens, so a
    // second tap on the same pixel hits an inert control, not this one
    // again. This also fires _handleTextChanged (TextEditingController
    // notifies synchronously), which already forwards the now-empty text —
    // the explicit call right after is harmless, idempotent redundancy for
    // clarity, not a second real stop.
    _controller.clear();
    widget.onTypingTextChanged?.call('');
    widget.onSend(text);
  }

  Future<void> _pickAttachment() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: AppColors.primary,
                ),
                title: Text(l10n.inboxChooseFromGallery),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppColors.secondary,
                ),
                title: Text(l10n.inboxTakePhoto),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (source == null || !mounted) return;

    final file = await _attachmentPicker.pick(
      context,
      source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null || !mounted) return; // cancelled, denied, or failed

    setState(() => _pendingAttachment = file);
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
      _focusNode.requestFocus();
      return;
    }
    // Hide the OS keyboard first so the emoji picker replaces it in the
    // same screen area rather than both trying to occupy space at once —
    // this is how switching keyboard -> emoji-picker happens.
    _focusNode.unfocus();
    setState(() => _showEmojiPicker = true);
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isSending) return;
    final path = await _voiceRecorder.start(context);
    if (path == null || !mounted) return; // permission denied/cancelled
    setState(() {
      _isRecording = true;
      _recordingStartedAt = DateTime.now();
    });
  }

  Future<void> _cancelRecording() async {
    await _voiceRecorder.cancel();
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _recordingStartedAt = null;
    });
  }

  Future<void> _stopRecording() async {
    final startedAt = _recordingStartedAt;
    final path = await _voiceRecorder.stop();
    if (!mounted) return;
    final duration = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);
    setState(() {
      _isRecording = false;
      _recordingStartedAt = null;
      // Guards against a near-instant tap/release producing an unplayably
      // short clip — treated the same as a cancel.
      if (path != null && duration.inMilliseconds >= 500) {
        _pendingVoice = _PendingVoice(path: path, duration: duration);
      }
    });
  }

  void _discardPendingVoice() {
    if (_isSending) return;
    setState(() => _pendingVoice = null);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final inertIconColor = isDark
        ? AppColors.textTertiaryDark
        : AppColors.textTertiaryLight;
    final canSend =
        (_hasText || _pendingAttachment != null || _pendingVoice != null) &&
        !_isSending;

    return PopScope(
      canPop: !_showEmojiPicker,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _showEmojiPicker = false);
      },
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.replyTarget != null)
              _ReplyPreviewBanner(
                replyTarget: widget.replyTarget!,
                peerName: widget.peerName,
                onClose: widget.onClearReply,
              ),
            if (_pendingAttachment != null)
              _AttachmentPreview(
                file: _pendingAttachment!,
                onRemove: _isSending
                    ? null
                    : () => setState(() => _pendingAttachment = null),
              ),
            if (_isRecording)
              _RecordingBar(onCancel: _cancelRecording, onStop: _stopRecording)
            else if (_pendingVoice != null)
              _VoicePreviewBar(
                path: _pendingVoice!.path,
                duration: _pendingVoice!.duration,
                onRemove: _isSending ? null : _discardPendingVoice,
                onSend: canSend ? _submit : null,
              )
            else
              _buildComposerRow(context, l10n, inertIconColor, canSend),
            if (_showEmojiPicker)
              EmojiPicker(
                textEditingController: _controller,
                config: const Config(height: 250),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposerRow(
    BuildContext context,
    AppLocalizations l10n,
    Color inertIconColor,
    bool canSend,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          tooltip: l10n.inboxComposerAttach,
          onPressed: _isSending ? null : _pickAttachment,
          color: inertIconColor,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(
              minHeight: AppTouchTarget.minSize,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceVariantDark
                  : AppColors.surfaceVariantLight,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _isFocused ? AppColors.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            // The ONE visible surface/border for the whole composer
            // lives on this outer container. The TextField below must
            // stay fully transparent and borderless — the app's global
            // `InputDecorationTheme` (core/theme/app_theme.dart, used
            // by every real form field) sets its own `filled`/
            // `fillColor`/`enabledBorder`/`focusedBorder`. Overriding
            // only `border:` in a local InputDecoration does NOT clear
            // those — `InputDecoration.applyDefaults` still falls back
            // to the theme's `enabledBorder`/`focusedBorder` for
            // whichever state is active, since only the generic
            // fallback was overridden. That's what produced the
            // "double/nested border" look: this container's own
            // border/fill PLUS the theme's own OutlineInputBorder
            // drawn again just inside it. Every state-specific field
            // must be overridden explicitly, not just `border`.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    style: AppTypography.bodyMedium,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: l10n.inboxComposerHint,
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                IconButton(
                  tooltip: l10n.inboxComposerEmoji,
                  onPressed: _isSending ? null : _toggleEmojiPicker,
                  color: _showEmojiPicker ? AppColors.primary : inertIconColor,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _showEmojiPicker
                        ? Icons.keyboard_alt_outlined
                        : Icons.emoji_emotions_outlined,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: RotationTransition(
              turns: animation.drive(Tween(begin: 0.75, end: 1)),
              child: child,
            ),
          ),
          child: _hasText || _pendingAttachment != null
              ? IconButton(
                  key: const ValueKey('send'),
                  tooltip: l10n.inboxComposerSend,
                  onPressed: canSend ? _submit : null,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  color: AppColors.primary,
                )
              : IconButton(
                  key: const ValueKey('voice'),
                  tooltip: l10n.inboxComposerVoice,
                  onPressed: _isSending ? null : _startRecording,
                  color: inertIconColor,
                  icon: const Icon(Icons.mic_none_rounded),
                ),
        ),
      ],
    );
  }
}

/// Reply preview banner shown above the composer row while
/// [ChatComposer.replyTarget] is set — sender name, a one-line preview of
/// the original (text, or a type label for media, matching
/// `conversationPreview`'s inbox-list labels), a thumbnail for an image
/// reply, and a close button that clears the reply without sending
/// anything.
class _ReplyPreviewBanner extends StatelessWidget {
  final MessageEntity replyTarget;
  final String peerName;
  final VoidCallback? onClose;

  const _ReplyPreviewBanner({
    required this.replyTarget,
    required this.peerName,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final senderLabel = replyTarget.isMine ? 'You' : peerName;
    final showThumbnail =
        !replyTarget.isDeleted &&
        replyTarget.type == MessageType.image &&
        replyTarget.attachmentUrl != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceVariantDark
            : AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderLabel,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  replyTarget.isDeleted
                      ? 'This message was deleted'
                      : conversationPreview(replyTarget),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
          if (showThumbnail) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 40,
                height: 40,
                child: replyTarget.attachmentUrl!.startsWith('http')
                    ? Image.network(
                        replyTarget.attachmentUrl!,
                        fit: BoxFit.cover,
                      )
                    : NmLocalMediaImage(
                        source: replyTarget.attachmentUrl!,
                        // 40x40 thumbnail — decode to size, not full photo.
                        cacheWidth:
                            (40 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                      ),
              ),
            ),
          ],
          IconButton(
            tooltip: AppLocalizations.of(context).inboxCancelReply,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  final XFile file;
  final VoidCallback? onRemove;

  const _AttachmentPreview({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: NmLocalMediaImage(
                source: file.path,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                cacheWidth: (64 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
              ),
            ),
            Positioned(
              top: -8,
              right: -8,
              child: Tooltip(
                message: l10n.inboxRemoveAttachment,
                child: InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(12),
                  child: const CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.error,
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown while [VoiceRecorderService.start] is active — replaces the whole
/// composer row (rather than overlapping the text field) so there is
/// nothing ambiguous to lay out and no risk of bottom overflow.
class _RecordingBar extends StatefulWidget {
  final VoidCallback onCancel;
  final VoidCallback onStop;

  const _RecordingBar({required this.onCancel, required this.onStop});

  @override
  State<_RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<_RecordingBar> {
  final _stopwatch = Stopwatch()..start();
  late final Timer _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    // Purely a local display tick — the authoritative recording duration
    // used when building the pending voice message is computed separately
    // by `_ChatComposerState._stopRecording` from its own start timestamp.
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() => _elapsed = _stopwatch.elapsed);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      constraints: const BoxConstraints(minHeight: AppTouchTarget.minSize),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceVariantDark
            : AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: AppLocalizations.of(context).inboxCancelRecording,
            onPressed: widget.onCancel,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.error,
            ),
          ),
          const _RecordingDot(),
          const SizedBox(width: 8),
          Text(
            _formatDuration(_elapsed),
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: AppLocalizations.of(context).inboxStopAndPreview,
            onPressed: widget.onStop,
            icon: const Icon(
              Icons.stop_circle_rounded,
              color: AppColors.primary,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Small pulsing red dot indicating an active recording.
class _RecordingDot extends StatefulWidget {
  const _RecordingDot();

  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);
  late final Animation<double> _opacity = Tween(
    begin: 0.3,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: const CircleAvatar(radius: 5, backgroundColor: AppColors.error),
    );
  }
}

/// Recorded-but-not-yet-sent voice note — lets the user play/pause the
/// local recording before deciding to send or discard it. Owns its own
/// [AudioPlayer], separate from the one each sent [message_bubble.dart]
/// bubble uses, disposed with this widget.
class _VoicePreviewBar extends StatefulWidget {
  final String path;
  final Duration duration;
  final VoidCallback? onRemove;
  final VoidCallback? onSend;

  const _VoicePreviewBar({
    required this.path,
    required this.duration,
    required this.onRemove,
    required this.onSend,
  });

  @override
  State<_VoicePreviewBar> createState() => _VoicePreviewBarState();
}

class _VoicePreviewBarState extends State<_VoicePreviewBar> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _stateSub = _player.onPlayerStateChanged.listen((playerState) {
      if (!mounted) return;
      setState(() {
        _isPlaying = playerState == PlayerState.playing;
        if (playerState == PlayerState.completed) _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    unawaited(_positionSub?.cancel());
    unawaited(_stateSub?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play(DeviceFileSource(widget.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final total = widget.duration.inMilliseconds == 0
        ? const Duration(seconds: 1)
        : widget.duration;
    final progress = (_position.inMilliseconds / total.inMilliseconds).clamp(
      0.0,
      1.0,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      constraints: const BoxConstraints(minHeight: AppTouchTarget.minSize),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceVariantDark
            : AppColors.surfaceVariantLight,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: AppLocalizations.of(context).inboxDiscardRecording,
            onPressed: widget.onRemove,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.error,
            ),
          ),
          IconButton(
            tooltip: _isPlaying ? 'Pause' : 'Play',
            onPressed: _togglePlay,
            icon: Icon(
              _isPlaying
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              color: AppColors.primary,
              size: 30,
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDuration(
              _isPlaying || _position > Duration.zero
                  ? _position
                  : widget.duration,
            ),
            style: AppTypography.labelSmall,
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).inboxSendVoiceMessage,
            onPressed: widget.onSend,
            icon: const Icon(Icons.send_rounded, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
