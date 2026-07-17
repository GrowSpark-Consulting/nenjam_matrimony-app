import 'package:flutter/material.dart';

import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../discover/presentation/widgets/compatibility_badge.dart';
import '../../../../core/widgets/cards/profile_card.dart';

/// A search result: the existing [NmProfileCard] design, unmodified, with
/// the compatibility score composed on top via [CompatibilityBadge] rather
/// than a redesigned card.
///
/// Action mapping onto the card's existing callback slots — no new buttons,
/// no card redesign: [onTap] (whole card) = View Profile,
/// [onInterested] (heart icon) = Interested, [onShortlist] (bookmark icon)
/// = Shortlist.
class SearchResultCard extends StatelessWidget {
  final DiscoveryProfileEntity profile;
  final VoidCallback? onTap;
  final VoidCallback? onInterested;
  final VoidCallback? onShortlist;

  const SearchResultCard({
    super.key,
    required this.profile,
    this.onTap,
    this.onInterested,
    this.onShortlist,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NmProfileCard(
          name: profile.name,
          age: '${profile.age}',
          location: profile.location,
          imageUrl: profile.photoUrls.isNotEmpty ? profile.photoUrls.first : null,
          profession: profile.profession,
          gender: profile.gender,
          isVerified: profile.isVerified,
          isPremium: profile.isPremium,
          isOnline: profile.isOnline,
          onTap: onTap,
          onLikeTap: onInterested,
          onShortlistTap: onShortlist,
          heroTag: 'profile-photo-${profile.id}',
        ),
        if (profile.compatibility.aiMatchPercent > 0)
          Positioned(
            top: 12,
            right: 12,
            child: CompatibilityBadge(compatibility: profile.compatibility),
          ),
      ],
    );
  }
}
