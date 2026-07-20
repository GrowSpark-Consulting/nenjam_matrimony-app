import 'package:flutter/material.dart';

/// Mirrors `NmVerificationStatus` 1:1 so mapping between the two at the
/// call site is a trivial switch, without coupling this domain entity to a
/// presentation-layer widget's enum.
enum TrustItemStatus { verified, pending, incomplete }

class TrustItemEntity {
  final IconData icon;
  final String label;
  final TrustItemStatus status;

  const TrustItemEntity({
    required this.icon,
    required this.label,
    required this.status,
  });
}

class TrustScoreEntity {
  final int overallPercent;
  final List<TrustItemEntity> items;

  const TrustScoreEntity({
    this.overallPercent = 0,
    this.items = const [],
  });
}
