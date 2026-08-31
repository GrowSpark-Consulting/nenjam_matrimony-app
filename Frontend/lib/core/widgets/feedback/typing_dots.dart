import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Three bouncing dots — the universal "typing…" animation. Kept as a
/// standalone core primitive (rather than baked into any one card/bubble
/// widget) so both a conversation row and a chat-thread bubble can use the
/// exact same animation.
class NmTypingDots extends StatefulWidget {
  final double dotSize;
  final Color? color;

  const NmTypingDots({super.key, this.dotSize = 6, this.color});

  @override
  State<NmTypingDots> createState() => _NmTypingDotsState();
}

class _NmTypingDotsState extends State<NmTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.textTertiaryLight;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = (_controller.value - (i * 0.2)) % 1.0;
            final bounce = t < 0.5 ? t * 2 : (1 - t) * 2;
            return Padding(
              padding: EdgeInsets.only(
                right: i == 2 ? 0 : widget.dotSize * 0.5,
              ),
              child: Transform.translate(
                offset: Offset(0, -bounce * widget.dotSize * 0.6),
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
