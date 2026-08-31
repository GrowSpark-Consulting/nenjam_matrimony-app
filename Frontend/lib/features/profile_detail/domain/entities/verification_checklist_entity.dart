import 'package:flutter/material.dart';

/// Mirrors `NmVerificationStatus` 1:1 so mapping between the two at the
/// call site is a trivial switch, without coupling this domain entity to a
/// presentation-layer widget's enum.
enum VerificationItemStatus { verified, pending, incomplete }

class VerificationItemEntity {
  final IconData icon;
  final String label;
  final VerificationItemStatus status;

  const VerificationItemEntity({
    required this.icon,
    required this.label,
    required this.status,
  });
}

/// The itemized verification checklist shown on a member's profile —
/// phone, email, government ID, face match. Deliberately carries no
/// aggregate percentage: there is no scoring concept attached to it.
class VerificationChecklistEntity {
  final List<VerificationItemEntity> items;

  const VerificationChecklistEntity({this.items = const []});
}
