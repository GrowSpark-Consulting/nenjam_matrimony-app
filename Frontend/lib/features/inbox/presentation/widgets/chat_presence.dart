import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/avatars/app_avatars.dart';
import '../../../../core/widgets/feedback/pulse_dot.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/presence_state.dart';
import '../providers/presence_providers.dart';
import '../utils/last_seen_formatter.dart';

/// Three softly-pulsing dots for the "Typing…" affordance. One lightweight
/// [AnimationController] drives a staggered opacity across the dots — no heavy
/// animation, and [RepaintBoundary]'d so it never repaints its neighbours.
class PresenceDots extends StatefulWidget {
  final Color color;
  final double size;

  const PresenceDots({super.key, required this.color, this.size = 4});

  @override
  State<PresenceDots> createState() => _PresenceDotsState();
}

class _PresenceDotsState extends State<PresenceDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_controller.value + i / 3) % 1.0;
            // Triangle wave 0.3 → 1 → 0.3 so each dot fades in and out in turn.
            final opacity = (0.3 + (0.5 - (phase - 0.5).abs()) * 1.4).clamp(0.3, 1.0);
            return Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : widget.size * 0.7),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// The chat header's status line under the peer's name. Reads the live presence
/// cache for [userId] only (so nothing else in the header rebuilds) and renders,
/// by priority: **Typing… ▸ Online ▸ Last seen …**, cross-fading between states
/// without a layout jump.
class ChatPresenceSubtitle extends ConsumerWidget {
  final String userId;

  /// Already-localized "Online" label.
  final String onlineLabel;
  final String? locale;

  const ChatPresenceSubtitle({
    super.key,
    required this.userId,
    required this.onlineLabel,
    this.locale,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presence = ref.watch(peerPresenceProvider(userId));
    final (key, child) = _content(presence, AppLocalizations.of(context));

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
      // Swap (and fade) only when the rendered status actually changes.
      child: KeyedSubtree(key: ValueKey(key), child: child),
    );
  }

  (String, Widget) _content(PresenceState? presence, AppLocalizations l10n) {
    if (presence == null) return ('none', const SizedBox(height: 14));
    if (presence.isTyping) {
      return (
        'typing',
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.inboxTyping, style: _typingStyle),
            const SizedBox(width: 4),
            const PresenceDots(color: AppColors.online),
          ],
        ),
      );
    }
    if (presence.isOnline) {
      return (
        'online',
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NmPulseDot(size: 8, color: AppColors.online),
            const SizedBox(width: 6),
            Text(onlineLabel, style: _onlineStyle),
          ],
        ),
      );
    }
    if (presence.lastSeen != null) {
      final text = LastSeenFormatter.detailed(presence.lastSeen!, l10n);
      return ('lastseen:$text', Text(text, style: _lastSeenStyle));
    }
    return ('none', const SizedBox(height: 14));
  }

  TextStyle get _typingStyle => AppTypography.labelSmall.copyWith(
        color: AppColors.online,
        fontWeight: FontWeight.w600,
      );

  TextStyle get _onlineStyle => AppTypography.labelSmall.copyWith(
        color: AppColors.online,
        fontWeight: FontWeight.w600,
      );

  TextStyle get _lastSeenStyle => AppTypography.labelSmall.copyWith(
        color: AppColors.textTertiaryLight,
        fontWeight: FontWeight.w600,
      );
}

/// The header avatar with its online dot driven by the live presence cache
/// (rebuilds only when this peer's online flag flips, via a narrow `select`).
class PresenceAvatar extends ConsumerWidget {
  final String userId;
  final String? imageUrl;
  final double size;
  final String gender;

  const PresenceAvatar({
    super.key,
    required this.userId,
    required this.imageUrl,
    required this.gender,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(
      presenceProvider.select((m) => m[userId]?.isOnline ?? false),
    );
    return NmOnlineAvatar(
      imageUrl: imageUrl,
      isOnline: isOnline,
      size: size,
      gender: gender,
    );
  }
}
