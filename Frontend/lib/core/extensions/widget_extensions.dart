import 'package:flutter/material.dart';

import '../constants/app_spacing.dart';

/// Widget extensions for padding, margin, and alignment convenience.
extension WidgetExtensions on Widget {
  // ─── Padding ─────────────────────────────────────────────────────
  Widget paddingAll(double value) =>
      Padding(padding: EdgeInsets.all(value), child: this);

  Widget paddingSymmetric({
    double horizontal = 0,
    double vertical = 0,
  }) =>
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontal,
          vertical: vertical,
        ),
        child: this,
      );

  Widget paddingOnly({
    double left = 0,
    double top = 0,
    double right = 0,
    double bottom = 0,
  }) =>
      Padding(
        padding: EdgeInsets.only(
          left: left,
          top: top,
          right: right,
          bottom: bottom,
        ),
        child: this,
      );

  Widget get paddingPage =>
      Padding(padding: AppSpacing.pagePadding, child: this);

  Widget get paddingHorizontal =>
      Padding(padding: AppSpacing.pageHorizontal, child: this);

  // ─── Alignment ───────────────────────────────────────────────────
  Widget get center => Center(child: this);

  Widget align(AlignmentGeometry alignment) =>
      Align(alignment: alignment, child: this);

  Widget get alignLeft => Align(alignment: Alignment.centerLeft, child: this);

  Widget get alignRight => Align(alignment: Alignment.centerRight, child: this);

  // ─── Sizing ──────────────────────────────────────────────────────
  Widget expanded({int flex = 1}) => Expanded(flex: flex, child: this);

  Widget flexible({int flex = 1, FlexFit fit = FlexFit.loose}) =>
      Flexible(flex: flex, fit: fit, child: this);

  Widget sizedBox({double? width, double? height}) =>
      SizedBox(width: width, height: height, child: this);

  // ─── Decoration ──────────────────────────────────────────────────
  Widget withDecoration(BoxDecoration decoration) =>
      DecoratedBox(decoration: decoration, child: this);

  // ─── Visibility ──────────────────────────────────────────────────
  Widget visible(bool isVisible) =>
      Visibility(visible: isVisible, child: this);

  Widget opacity(double value) => Opacity(opacity: value, child: this);

  // ─── Gesture ─────────────────────────────────────────────────────
  Widget onTap(VoidCallback? onTap) =>
      GestureDetector(onTap: onTap, child: this);

  Widget inkWell({
    VoidCallback? onTap,
    BorderRadius? borderRadius,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? BorderRadius.circular(12),
        child: this,
      );

  // ─── Semantic ────────────────────────────────────────────────────
  Widget semanticLabel(String label) =>
      Semantics(label: label, child: this);

  // ─── Safe Area ───────────────────────────────────────────────────
  Widget get safeArea => SafeArea(child: this);

  Widget safeAreaOnly({
    bool top = true,
    bool bottom = true,
    bool left = true,
    bool right = true,
  }) =>
      SafeArea(
        top: top,
        bottom: bottom,
        left: left,
        right: right,
        child: this,
      );
}

/// SizedBox gap helpers for consistent spacing.
extension GapExtension on num {
  SizedBox get verticalGap => SizedBox(height: toDouble());
  SizedBox get horizontalGap => SizedBox(width: toDouble());
}
