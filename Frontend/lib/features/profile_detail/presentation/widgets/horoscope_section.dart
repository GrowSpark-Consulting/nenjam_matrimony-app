import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/widgets/relationship_intelligence/horoscope_compatibility_section.dart';
import '../../domain/entities/profile_detail_entity.dart';

/// Stacks the viewed member's own horoscope facts above the guna-match
/// comparison — [HoroscopeCompatibilitySection]'s comparison mode is the
/// exact seam its own doc comment flags for "a future view-other-member
/// screen", reused unmodified here.
class HoroscopeSection extends StatelessWidget {
  final ProfileDetailEntity detail;

  const HoroscopeSection({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final horoscope = detail.horoscope;
    final astroScore = detail.base.compatibility.astroMatchPercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HoroscopeCompatibilitySection(
          rasi: horoscope.rasi,
          nakshatra: horoscope.nakshatra,
          dosham: horoscope.dosham,
          matchingEnabled: horoscope.matchingEnabled,
        ),
        if (astroScore > 0) ...[
          const SizedBox(height: AppSpacing.md),
          HoroscopeCompatibilitySection(
            compatibilityScore: astroScore,
            matchingPoints: horoscope.matchingPoints,
            partnerName: detail.base.name,
          ),
        ],
      ],
    );
  }
}
