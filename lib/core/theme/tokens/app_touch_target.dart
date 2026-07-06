import 'package:flutter/material.dart';

/// Nenjam Matrimony — Accessibility Touch Target Tokens
///
/// Enforces minimum 48dp touch target rules across Apple & Android guidelines.
abstract final class AppTouchTarget {
  static const double minSize = 48.0;
  static const BoxConstraints minConstraints = BoxConstraints(
    minWidth: minSize,
    minHeight: minSize,
  );
}
