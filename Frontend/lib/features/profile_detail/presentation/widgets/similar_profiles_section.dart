import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/profile_navigation.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/profile_card.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../providers/profile_detail_providers.dart';

/// Horizontal shelf of profiles similar to the one being viewed.
/// Tapping a card recurses into the same route — the back stack grows
/// Detail(A) → Detail(B), popping one at a time.
class SimilarProfilesSection extends ConsumerWidget {
  final DiscoveryProfileEntity baseProfile;

  const SimilarProfilesSection({super.key, required this.baseProfile});

  // NmProfileCard no longer derives its own height from an internal
  // AspectRatio — its image fills whatever height it's given via Expanded,
  // so the card can never overflow regardless of the number below. This
  // shelf (the parent) is what determines that height: 264 comfortably
  // fits a 160-wide photo plus the footer, with room to spare.
  static const double _cardWidth = 160;
  static const double _cardHeight = 264;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final similarAsync = ref.watch(similarProfilesProvider(baseProfile));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Similar Profiles', style: AppTypography.titleLarge),
        const SizedBox(height: AppSpacing.base),
        SizedBox(
          height: _cardHeight,
          child: similarAsync.when(
            data: (profiles) {
              if (profiles.isEmpty) return const SizedBox.shrink();
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: profiles.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final profile = profiles[index];
                  return SizedBox(
                    width: _cardWidth,
                    child: NmProfileCard(
                      name: profile.name,
                      age: '${profile.age}',
                      location: profile.location,
                      imageUrl: profile.photoUrls.isNotEmpty
                          ? profile.photoUrls.first
                          : null,
                      profession: profile.profession,
                      gender: profile.gender,
                      isVerified: profile.isVerified,
                      isPremium: profile.isPremium,
                      isOnline: profile.isOnline,
                      onTap: () => openProfileDetail(context, profile),
                      heroTag: 'profile-photo-${profile.id}',
                    ),
                  );
                },
              );
            },
            loading: () => ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) => const SizedBox(
                width: _cardWidth,
                child: NmShimmer(
                  height: _cardHeight,
                  borderRadius: AppSpacing.radiusXl,
                ),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
