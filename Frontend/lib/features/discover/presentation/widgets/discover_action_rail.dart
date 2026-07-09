import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';

/// Bottom action buttons for the Discover reel card, matching the Stitch design:
///
/// ┌──────────────────────────────────┐
/// │       ❤ Interested (gold full)   │
/// ├─────────────────┬────────────────┤
/// │ 🔖 Shortlist    │ 👤 View Profile │
/// └─────────────────┴────────────────┘
///
/// State is local: Interested toggles to "Interest Sent" for 3 s.
class DiscoverActionRail extends StatefulWidget {
  final VoidCallback? onInterested;
  final VoidCallback? onShortlist;
  final VoidCallback? onShare;

  const DiscoverActionRail({
    super.key,
    this.onInterested,
    this.onShortlist,
    this.onShare,
  });

  @override
  State<DiscoverActionRail> createState() => _DiscoverActionRailState();
}

class _DiscoverActionRailState extends State<DiscoverActionRail>
    with SingleTickerProviderStateMixin {
  bool _interestSent = false;
  bool _shortlisted = false;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _pulse = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleInterested() async {
    if (_interestSent) return;
    await _pulseCtrl.forward();
    await _pulseCtrl.reverse();
    widget.onInterested?.call();
    setState(() => _interestSent = true);
    await Future<void>.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _interestSent = false);
  }

  void _handleShortlist() {
    widget.onShortlist?.call();
    setState(() => _shortlisted = !_shortlisted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Interested Button (full-width gold) ──────────────────
        ScaleTransition(
          scale: _pulse,
          child: _InterestedButton(
            sent: _interestSent,
            onTap: _handleInterested,
            label: _interestSent
                ? l10n.discoverInterestSentLabel
                : l10n.actionInterested,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── Shortlist + View Profile ──────────────────────────────
        Row(
          children: [
            Expanded(
              child: _GlassButton(
                icon: _shortlisted
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                label: l10n.profileCardShortlist,
                iconColor: _shortlisted
                    ? AppColors.accentGoldLight
                    : Colors.white,
                onTap: _handleShortlist,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _GlassButton(
                icon: Icons.person_rounded,
                label: l10n.actionViewProfile,
                onTap: widget.onShare, // wired to share/view callback
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InterestedButton extends StatelessWidget {
  final bool sent;
  final VoidCallback? onTap;
  final String label;

  const _InterestedButton({
    required this.sent,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: sent ? null : AppGradients.gold,
              color: sent ? AppColors.faceVerificationGreen : null,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              boxShadow: sent ? null : AppShadows.goldGlow,
            ),
            child: Container(
              height: 54,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    sent
                        ? Icons.check_circle_rounded
                        : Icons.favorite_rounded,
                    size: 20,
                    color: sent ? Colors.white : AppColors.textOnGold,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    label,
                    style: AppTypography.button.copyWith(
                      color: sent ? Colors.white : AppColors.textOnGold,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color iconColor;

  const _GlassButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: SizedBox(
              height: 46,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: iconColor),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      label,
                      style: AppTypography.labelMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
