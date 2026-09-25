import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// A small, quiet "this field is fetching its options" indicator for the
/// trailing slot of an input — a soft lavender track with a rounded plum arc
/// sweeping around it.
///
/// Meant for the short (1–2s) master-data fetches behind the State / City /
/// Religion / Community pickers, where a stock [CircularProgressIndicator]
/// reads as heavier and busier than the wait deserves. It occupies exactly
/// `size x size`, so it swaps in and out of a suffix slot without nudging
/// the field's text or height.
///
/// Only the rotation animates, via a [RotationTransition] over a painter that
/// never repaints, so each frame is a transform on a cached layer. When the
/// platform asks for reduced motion the arc is shown still.
class NmFieldLoader extends StatefulWidget {
  const NmFieldLoader({
    super.key,
    this.size = 18,
    this.strokeWidth = 2,
    this.color = AppColors.primary,
    this.trackColor = AppColors.primarySurfaceStrong,
  });

  final double size;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  State<NmFieldLoader> createState() => _NmFieldLoaderState();
}

class _NmFieldLoaderState extends State<NmFieldLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Align rather than a bare SizedBox: an InputDecorator suffix slot
    // imposes a minimum size (32x32 via `suffixIconConstraints`), which a
    // SizedBox alone would be stretched to — a 28x32 ring that crowds the
    // field's border. Align loosens that, so the ring stays `size x size`
    // and sits centred in whatever box the slot insists on.
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: RotationTransition(
            turns: _controller,
            child: CustomPaint(
              painter: _ArcPainter(
                color: widget.color,
                trackColor: widget.trackColor,
                strokeWidth: widget.strokeWidth,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height,
    ).deflate(strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = trackColor);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 0.6,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
