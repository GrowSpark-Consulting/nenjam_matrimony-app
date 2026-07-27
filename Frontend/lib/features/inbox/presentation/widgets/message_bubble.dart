import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/message_entity.dart';

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

  const MessageBubble({super.key, required this.message, this.onRetry});

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
          child: _MessageBubbleContent(message: widget.message, onRetry: widget.onRetry),
        ),
      ),
    );
  }
}

class _MessageBubbleContent extends StatelessWidget {
  final MessageEntity message;
  final ValueChanged<String>? onRetry;

  const _MessageBubbleContent({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
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

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: EdgeInsets.fromLTRB(
        message.type == MessageType.image ? 6 : 14,
        message.type == MessageType.image ? 6 : 10,
        message.type == MessageType.image ? 6 : 14,
        10,
      ),
      decoration: BoxDecoration(
        color: bubbleColor,
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
          if (message.type == MessageType.image && message.attachmentUrl != null)
            _MessageImage(url: message.attachmentUrl!, sending: message.status == MessageStatus.sending)
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

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: canRetry
          ? InkWell(
              onTap: () => onRetry!(message.clientMessageId!),
              borderRadius: BorderRadius.circular(16),
              child: bubble,
            )
          : bubble,
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

/// An image message's thumbnail — [url] is either a real `http(s)` URL (a
/// received message, or one this client sent that's since been confirmed
/// with a hosted URL) or a local file path (an attachment still `sending`,
/// before any real upload endpoint exists — see
/// docs/development/chat-backend-handoff.md). Shows a dimming overlay +
/// spinner while `sending`.
class _MessageImage extends StatelessWidget {
  final String url;
  final bool sending;

  const _MessageImage({required this.url, required this.sending});

  @override
  Widget build(BuildContext context) {
    final image = url.startsWith('http')
        ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _MessageImageError())
        : Image.file(File(url), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _MessageImageError());

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 160, minHeight: 160, maxHeight: 260),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
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
