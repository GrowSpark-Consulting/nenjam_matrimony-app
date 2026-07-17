import 'package:flutter/material.dart';

import '../../../../core/widgets/cards/compatibility_card.dart';
import '../../domain/entities/profile_detail_entity.dart';

/// AI Match Compatibility — [NmCompatibilityCard] reused unmodified, fed
/// from `base.compatibility` (already computed upstream by whichever feed
/// this profile was tapped from).
class CompatibilityCardSection extends StatelessWidget {
  final ProfileDetailEntity detail;

  const CompatibilityCardSection({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final compatibility = detail.base.compatibility;
    final matchingPoints = <String>[
      if (compatibility.lifestyleMatchPercent >= 80) 'Strong lifestyle alignment',
      if (compatibility.familyMatchPercent >= 80) 'Compatible family values',
      if (compatibility.educationMatchPercent >= 80) 'Matched education background',
      if (compatibility.valuesMatchPercent >= 80) 'Shared core values',
      if (compatibility.goalsMatchPercent >= 80) 'Aligned life goals',
    ];

    return NmCompatibilityCard(
      score: compatibility.overallCompatibility,
      title: 'AI Match Compatibility',
      matchingPoints: matchingPoints,
    );
  }
}
