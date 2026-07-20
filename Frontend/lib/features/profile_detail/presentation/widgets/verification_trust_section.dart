import 'package:flutter/material.dart';

import '../../../profile/presentation/widgets/verification_card.dart';
import '../../domain/entities/profile_detail_entity.dart';
import '../../domain/entities/trust_score_entity.dart';

/// Verification checklist ([NmVerificationCard]) for the "Verification"
/// tab. The trust-score ring headline now lives at the top of the page
/// as [TrustScoreCard] — this section is just the itemized breakdown.
class VerificationTrustSection extends StatelessWidget {
  final ProfileDetailEntity detail;

  const VerificationTrustSection({super.key, required this.detail});

  static NmVerificationStatus _mapStatus(TrustItemStatus status) {
    switch (status) {
      case TrustItemStatus.verified:
        return NmVerificationStatus.verified;
      case TrustItemStatus.pending:
        return NmVerificationStatus.pending;
      case TrustItemStatus.incomplete:
        return NmVerificationStatus.incomplete;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trust = detail.trustScore;
    if (trust.items.isEmpty) return const SizedBox.shrink();

    return NmVerificationCard(
      items: [
        for (final item in trust.items)
          NmVerificationItem(
            icon: item.icon,
            label: item.label,
            status: _mapStatus(item.status),
          ),
      ],
    );
  }
}
