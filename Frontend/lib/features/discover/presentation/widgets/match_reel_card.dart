import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../domain/entities/discovery_profile_entity.dart';
import 'compatibility_badge.dart';
import 'discover_action_rail.dart';
import 'profile_info_overlay.dart';

/// Full-screen Reels-style profile card for the Discover tab.
///
/// Layout (layers from back to front):
///   1. Full-bleed profile photo
///   2. Strong bottom-to-top gradient scrim
///   3. Top: CompatibilityBadgeRow (AI %, Astro %, Trust)
///   4. Bottom: ProfileInfoOverlay + DiscoverActionRail
///
/// Uses [RepaintBoundary] to isolate repaints during scroll.
class MatchReelCard extends StatelessWidget {
  final DiscoveryProfileEntity profile;
  final VoidCallback? onInterested;
  final VoidCallback? onShortlist;
  final VoidCallback? onShare;

  const MatchReelCard({
    super.key,
    required this.profile,
    this.onInterested,
    this.onShortlist,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── 1. Background photo ──────────────────────────────────
          _ProfileImage(photoUrls: profile.photoUrls),

          // ── 2. Gradient overlay (transparent → dark bottom) ──────
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppGradients.imageOverlayStrong,
            ),
          ),

          // ── 3. Content ───────────────────────────────────────────
          Positioned.fill(
            child: SafeArea(
              child: _CardContent(
                profile: profile,
                onInterested: onInterested,
                onShortlist: onShortlist,
                onShare: onShare,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Lays out badge row at top + info/actions at bottom.
/// Uses a Column with [Spacer] to push content to top/bottom edges.
class _CardContent extends StatelessWidget {
  final DiscoveryProfileEntity profile;
  final VoidCallback? onInterested;
  final VoidCallback? onShortlist;
  final VoidCallback? onShare;

  const _CardContent({
    required this.profile,
    this.onInterested,
    this.onShortlist,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── TOP: score badges ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                AppSpacing.sm,
                AppSpacing.base,
                0,
              ),
              child: CompatibilityBadgeRow(
                compatibility: profile.compatibility,
                isVerified: profile.isVerified,
                isPremium: profile.isPremium,
              ),
            ),

            const Spacer(),

            // ── BOTTOM: profile info + action buttons ──────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                0,
                AppSpacing.base,
                AppSpacing.base,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileInfoOverlay(profile: profile),
                  const SizedBox(height: AppSpacing.base),
                  DiscoverActionRail(
                    onInterested: onInterested,
                    onShortlist: onShortlist,
                    onShare: onShare,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ProfileImage extends StatelessWidget {
  final List<String> photoUrls;

  const _ProfileImage({required this.photoUrls});

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) return _Placeholder();
    final url = photoUrls.first;

    // Local asset path
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return Image.asset(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _Placeholder(),
      );
    }

    // Network image — use FadeInImage for a smooth load experience
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _Placeholder(),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _Placeholder();
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryDark,
      child: const Center(
        child: Icon(
          Icons.person_rounded,
          size: 72,
          color: AppColors.textTertiaryDark,
        ),
      ),
    );
  }
}
