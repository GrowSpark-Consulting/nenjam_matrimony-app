import 'package:flutter/material.dart';

/// A single "milestone" row in a profile's activity timeline.
///
/// [timeAgo] is a pre-formatted relative-time string ("8 months ago") —
/// deliberately not a [DateTime], so no relative-time formatting logic is
/// needed downstream in the widget layer.
class TimelineEventEntity {
  final IconData icon;
  final String label;
  final String timeAgo;

  const TimelineEventEntity({
    required this.icon,
    required this.label,
    required this.timeAgo,
  });
}
