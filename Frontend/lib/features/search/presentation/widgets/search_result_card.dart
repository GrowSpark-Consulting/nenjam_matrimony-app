import 'package:flutter/material.dart';

import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../discover/presentation/widgets/compatibility_badge.dart';
import '../../../../core/widgets/cards/profile_card.dart';

/// A search result card — built around the existing [NmProfileCard],
/// unmodified (it's also used by Profile Detail's "similar profiles"
/// section, so changing it isn't scoped to this redesign), with richer
/// info composed into its existing text slots and the compatibility score
/// on top via [CompatibilityBadge].
///
/// [onTap] (whole card) = View Profile, [onInterested] (heart icon) =
/// Interested, [onShortlist] (bookmark icon) = Shortlist — same mapping as
/// before; a separate explicit "View" icon isn't added since the entire
/// card already opens the profile on tap, and a 3rd icon in this compact
/// 2-column grid cell's footer would overcrowd it.
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
          // Enriches the existing (already 1-line/ellipsis-safe) location
          // slot with height, rather than adding a new text row.
          location: profile.height.isEmpty
              ? profile.location
              : '${profile.location} • ${profile.height}',
          imageUrl: profile.photoUrls.isNotEmpty ? profile.photoUrls.first : null,
          // Same idea for profession — folds in religion/community so it
          // reads as one richer line instead of a second row.
          profession: _secondaryLine(),
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
            // NmProfileCard's own online dot sits at exactly top:12,
            // right:12 — shifting down when isOnline is true avoids this
            // badge silently covering it (a pre-existing collision: both
            // used the same anchor before).
            top: profile.isOnline ? 34 : 12,
            right: 12,
            child: CompatibilityBadge(compatibility: profile.compatibility),
          ),
      ],
    );
  }

  String _secondaryLine() {
    final parts = [
      if (profile.profession.isNotEmpty) profile.profession,
      if (profile.religion.isNotEmpty) profile.religion,
    ];
    return parts.join(' • ');
  }
}
