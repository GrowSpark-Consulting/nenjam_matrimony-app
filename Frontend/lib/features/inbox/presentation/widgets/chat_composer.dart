import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/tokens/app_touch_target.dart';
import '../../../../l10n/app_localizations.dart';

/// Message composer — the text field + send button are fully wired to
/// [MessagesNotifier.send]/`.sendImage`; the attach button opens the same
/// camera/gallery picker `PhotoManagerSection` uses for profile photos. The
/// emoji/voice buttons are present (so the layout matches a real chat
/// composer) but intentionally inert until there's a backend for voice
/// notes to go to.
class ChatComposer extends StatefulWidget {
  final ValueChanged<String> onSend;
  final Future<void> Function(File file) onSendAttachment;

  /// Fires `true` the moment the user starts typing (from empty), `false`
  /// ~2s after they stop, or immediately on send/clear/attachment-pick —
  /// hands off to [MessagesNotifier]'s (currently no-op) `setTyping` hook.
  /// Optional so this widget doesn't require a live typing backend to work.
  final ValueChanged<bool>? onTypingChanged;

  const ChatComposer({
    super.key,
    required this.onSend,
    required this.onSendAttachment,
    this.onTypingChanged,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _picker = ImagePicker();
  bool _hasText = false;
  bool _isFocused = false;
  bool _isSending = false;
  File? _pendingAttachment;
  Timer? _typingStopTimer;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
    _focusNode.addListener(() => setState(() => _isFocused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);

    final onTypingChanged = widget.onTypingChanged;
    if (onTypingChanged == null) return;
    _typingStopTimer?.cancel();
    if (hasText) {
      onTypingChanged(true);
      _typingStopTimer = Timer(const Duration(seconds: 2), () => onTypingChanged(false));
    } else {
      onTypingChanged(false);
    }
  }

  Future<void> _submit() async {
    if (_isSending) return; // guards a rapid double-tap on Send

    final attachment = _pendingAttachment;
    if (attachment != null) {
      setState(() {
        _isSending = true;
        _pendingAttachment = null;
      });
      _typingStopTimer?.cancel();
      widget.onTypingChanged?.call(false);
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
    // again.
    _controller.clear();
    _typingStopTimer?.cancel();
    widget.onTypingChanged?.call(false);
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
                leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                title: Text(l10n.inboxChooseFromGallery),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: AppColors.accentGold),
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

    final XFile? picked;
    try {
      picked = await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    } catch (_) {
      return;
    }
    if (picked == null || !mounted) return; // user cancelled

    setState(() => _pendingAttachment = File(picked!.path));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final inertIconColor = isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;
    final canSend = (_hasText || _pendingAttachment != null) && !_isSending;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingAttachment != null) _AttachmentPreview(
            file: _pendingAttachment!,
            onRemove: _isSending ? null : () => setState(() => _pendingAttachment = null),
          ),
          Row(
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
                  constraints: const BoxConstraints(minHeight: AppTouchTarget.minSize),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
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
                        onPressed: null,
                        color: inertIconColor,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.emoji_emotions_outlined, size: 22),
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
                  child: RotationTransition(turns: animation.drive(Tween(begin: 0.75, end: 1)), child: child),
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
                        onPressed: null,
                        color: inertIconColor,
                        icon: const Icon(Icons.mic_none_rounded),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  final File file;
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
              child: Image.file(file, width: 64, height: 64, fit: BoxFit.cover),
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
                    child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
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
