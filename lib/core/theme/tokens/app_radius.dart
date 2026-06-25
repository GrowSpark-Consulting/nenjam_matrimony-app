import 'package:flutter/material.dart';

/// Nenjam Matrimony — Centralized Radius System
///
/// Constants: 8, 12, 16, 20, 24, 32, 999.
abstract final class AppRadius {
  static const double r8 = 8.0;
  static const double r12 = 12.0;
  static const double r16 = 16.0;
  static const double r20 = 20.0;
  static const double r24 = 24.0;
  static const double r32 = 32.0;
  static const double r999 = 999.0; // Pill / Circle

  // BorderRadius helpers
  static final BorderRadius br8 = BorderRadius.circular(r8);
  static final BorderRadius br12 = BorderRadius.circular(r12);
  static final BorderRadius br16 = BorderRadius.circular(r16);
  static final BorderRadius br20 = BorderRadius.circular(r20);
  static final BorderRadius br24 = BorderRadius.circular(r24);
  static final BorderRadius br32 = BorderRadius.circular(r32);
  static final BorderRadius pill = BorderRadius.circular(r999);
}
