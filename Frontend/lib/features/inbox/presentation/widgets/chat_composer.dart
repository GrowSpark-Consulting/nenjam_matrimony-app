import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/tokens/app_touch_target.dart';
import '../../../../l10n/app_localizations.dart';

/// Message composer — the text field + send button are fully wired to
/// [MessagesNotifier.send]; the emoji/attachment/voice buttons are present
/// (so the layout matches a real chat composer) but intentionally inert
/// until there's a backend for attachments/voice notes to go to.
class ChatComposer extends StatefulWidget {
  final ValueChanged<String> onSend;

  const ChatComposer({super.key, required this.onSend});

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
    _focusNode.addListener(() => setState(() => _isFocused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final inertIconColor = isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: l10n.inboxComposerAttach,
            onPressed: null,
            color: inertIconColor,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              constraints: const BoxConstraints(minHeight: AppTouchTarget.minSize),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _isFocused ? AppColors.primary : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppTypography.bodyMedium,
                      decoration: InputDecoration(
                        hintText: l10n.inboxComposerHint,
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.inboxComposerEmoji,
                    onPressed: null,
                    color: inertIconColor,
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
            child: _hasText
                ? IconButton(
                    key: const ValueKey('send'),
                    tooltip: l10n.inboxComposerSend,
                    onPressed: _submit,
                    icon: const Icon(Icons.send_rounded),
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
    );
  }
}
