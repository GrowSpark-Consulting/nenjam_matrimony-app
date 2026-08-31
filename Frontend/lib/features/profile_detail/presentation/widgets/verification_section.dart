import 'package:flutter/material.dart';

import '../../../profile/presentation/widgets/verification_card.dart';
import '../../domain/entities/profile_detail_entity.dart';
import '../../domain/entities/verification_checklist_entity.dart';

/// Verification checklist ([NmVerificationCard]) for the "Verification"
/// tab — the itemized breakdown of which identity checks this member has
/// passed. There is no aggregate score above it.
class VerificationSection extends StatelessWidget {
  final ProfileDetailEntity detail;

  const VerificationSection({super.key, required this.detail});

  static NmVerificationStatus _mapStatus(VerificationItemStatus status) {
    switch (status) {
      case VerificationItemStatus.verified:
        return NmVerificationStatus.verified;
      case VerificationItemStatus.pending:
        return NmVerificationStatus.pending;
      case VerificationItemStatus.incomplete:
        return NmVerificationStatus.incomplete;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = detail.verification.items;
    if (items.isEmpty) return const SizedBox.shrink();

    return NmVerificationCard(
      items: [
        for (final item in items)
          NmVerificationItem(
            icon: item.icon,
            label: item.label,
            status: _mapStatus(item.status),
          ),
      ],
    );
  }
}
