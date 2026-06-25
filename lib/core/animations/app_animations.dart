import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/tokens/app_animation_tokens.dart';

/// Nenjam Matrimony — Reusable Luxury Animation Wrappers
abstract final class AppAnimations {
  /// Subtle luxury Fade in effect.
  static Widget fade(Widget child, {Duration? duration, Duration? delay}) {
    return child.animate(delay: delay).fadeIn(duration: duration ?? AppAnimationTokens.normal, curve: AppAnimationTokens.luxuryCurve);
  }

  /// Subtle Scale pop effect.
  static Widget scale(Widget child, {Duration? duration}) {
    return child.animate().scale(begin: const Offset(0.95, 0.95), duration: duration ?? AppAnimationTokens.fast, curve: AppAnimationTokens.luxuryCurve);
  }

  /// Subtle Slide up entry effect.
  static Widget slide(Widget child, {Duration? duration, double beginY = 0.1}) {
    return child.animate().slideY(begin: beginY, end: 0, duration: duration ?? AppAnimationTokens.normal, curve: AppAnimationTokens.luxuryCurve).fadeIn();
  }

  /// Button press micro-animation wrapper.
  static Widget buttonPress(Widget child) {
    return _AnimatedPress(child: child);
  }

  /// Card hover / touch micro-elevation effect.
  static Widget cardHover(Widget child) {
    return _AnimatedHover(child: child);
  }

  /// Hero transition helper.
  static Widget hero({required String tag, required Widget child}) {
    return Hero(tag: tag, child: child);
  }
}

class _AnimatedPress extends StatefulWidget {
  final Widget child;
  const _AnimatedPress({required this.child});

  @override
  State<_AnimatedPress> createState() => _AnimatedPressState();
}

class _AnimatedPressState extends State<_AnimatedPress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: AppAnimationTokens.fast,
        curve: AppAnimationTokens.buttonPressCurve,
        child: widget.child,
      ),
    );
  }
}

class _AnimatedHover extends StatefulWidget {
  final Widget child;
  const _AnimatedHover({required this.child});

  @override
  State<_AnimatedHover> createState() => _AnimatedHoverState();
}

class _AnimatedHoverState extends State<_AnimatedHover> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: AppAnimationTokens.normal,
        curve: AppAnimationTokens.cardHoverCurve,
        transform: _hovered ? (Matrix4.identity()..translateByDouble(0.0, -4.0, 0.0, 1.0)) : Matrix4.identity(),
        child: widget.child,
      ),
    );
  }
}
