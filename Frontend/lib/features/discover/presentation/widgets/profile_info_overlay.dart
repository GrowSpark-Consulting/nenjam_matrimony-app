import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../home/domain/entities/discovery_profile_entity.dart';

/// Bottom-of-card profile information overlay for the Discover reel.
///
/// Shows: name + age + verified badge, profession/location line,
/// secondary detail chips (location • religion • community), and
/// a Wrap of tag pills (NRI, Verified Identity, Premium Plus, etc.).
///
/// All sizing is adaptive — uses [LayoutBuilder] + [MediaQuery] so
/// there is zero overflow on 360 px screens.
class ProfileInfoOverlay extends StatelessWidget {
  final DiscoveryProfileEntity profile;

  const ProfileInfoOverlay({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Name + Age + Verified ──────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                '${profile.name}, ${profile.age}',
                style: AppTypography.headlineMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: [
                    const Shadow(blurRadius: 8, color: Colors.black54),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (profile.isVerified) ...[
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.verified_rounded,
                size: 22,
                color: AppColors.accentGoldLight,
              ),
            ],
          ],
        ),

        // ── Profession + Location line ─────────────────────────────
        if (profile.profession.isNotEmpty || profile.location.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs2),
          Text(
            [
              if (profile.location.isNotEmpty) profile.location,
              if (profile.profession.isNotEmpty) profile.profession,
            ].join(' • '),
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        // ── Secondary details: religion • community ────────────────
        if (_secondaryDetails.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          _SecondaryDetails(details: _secondaryDetails),
        ],

        // ── Tag pills ─────────────────────────────────────────────
        if (_tagPills.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: _tagPills.map((tag) => _TagPill(label: tag)).toList(),
          ),
        ],
      ],
    );
  }

  List<String> get _secondaryDetails => [
        if (profile.religion.isNotEmpty) profile.religion,
        if (profile.community.isNotEmpty) profile.community,
        if (profile.education.isNotEmpty) profile.education,
      ];

  List<String> get _tagPills {
    final pills = <String>[...profile.tags];
    if (profile.isVerified && !pills.contains('Verified')) {
      pills.insert(0, 'Verified');
    }
    if (profile.isPremium && !pills.contains('Premium Plus')) {
      pills.add('Premium Plus');
    }
    return pills.take(4).toList(); // cap at 4 to avoid runaway wrapping
  }
}

class _SecondaryDetails extends StatelessWidget {
  final List<String> details;

  const _SecondaryDetails({required this.details});

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.sizeOf(context).width * 0.7;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: details
            .map<Widget>(
              (d) => Text(
                d,
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white70,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
            .expand((w) => [w, const _Dot()])
            .toList()
          ..removeLast(),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => const Text(
        ' • ',
        style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold),
      );
}

/// Frosted-glass tag pill (NRI / Verified Identity / Premium Plus, etc.)
class _TagPill extends StatelessWidget {
  final String label;

  const _TagPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.labelSmall.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          fontSize: 10,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
