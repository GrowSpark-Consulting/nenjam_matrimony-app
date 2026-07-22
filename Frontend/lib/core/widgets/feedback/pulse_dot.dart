import 'package:flutter/material.dart';

/// A small filled circle with a soft, looping "breathing" pulse (a halo
/// ring that expands and fades around it) — the universal "this person is
/// online right now" cue. Kept as a standalone core primitive (like
/// [NmTypingDots]) so every online indicator across the app —
/// avatar-embedded or standalone — animates identically.
///
/// Reports the same `size x size` footprint as a plain static dot (the
/// halo is painted outside those bounds via [Clip.none], not by growing the
/// layout box), so it drops in for a static dot without shifting any
/// [Positioned] anchor that was tuned against the old, non-pulsing size.
class NmPulseDot extends StatefulWidget {
  final double size;
  final Color color;
  final Border? border;

  const NmPulseDot({super.key, this.size = 10, required this.color, this.border});

  @override
  State<NmPulseDot> createState() => _NmPulseDotState();
}

class _NmPulseDotState extends State<NmPulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: (1 - t) * 0.5,
                child: Container(
                  width: widget.size * (1 + t),
                  height: widget.size * (1 + t),
                  decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  border: widget.border,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
