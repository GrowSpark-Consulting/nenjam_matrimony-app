import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/layout/mouse_drag_scroll.dart';

/// Match Journey section — a horizontally scrollable milestone timeline.
///
/// Steps: Account Created → Profile Completed → Verified →
///        Interests → Conversations → Perfect Match
///
/// Completed steps show a green check, the current step pulses, and future
/// steps are greyed out and locked.
class NmMatchJourneyCard extends StatelessWidget {
  /// Index of the currently active step (0-based).
  final int currentStep;

  const NmMatchJourneyCard({super.key, this.currentStep = 3});

  /// Built per-locale rather than held as a `static const` — the labels are
  /// translated, so they can't be baked in at compile time. The two-line
  /// labels keep their embedded newline in both languages so the step
  /// captions stay the same height.
  static List<_JourneyStep> _stepsFor(AppLocalizations l10n) => [
    _JourneyStep(
      label: l10n.profileJourneyAccountCreated,
      icon: Icons.how_to_reg_rounded,
    ),
    _JourneyStep(
      label: l10n.profileJourneyProfileCompleted,
      icon: Icons.person_rounded,
    ),
    _JourneyStep(
      label: l10n.profileJourneyVerified,
      icon: Icons.verified_rounded,
    ),
    _JourneyStep(
      label: l10n.profileJourneyInterests,
      icon: Icons.favorite_rounded,
    ),
    _JourneyStep(
      label: l10n.profileJourneyConversations,
      icon: Icons.chat_bubble_rounded,
    ),
    _JourneyStep(
      label: l10n.profileJourneyPerfectMatch,
      icon: Icons.celebration_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).profileMatchJourney, style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              return NmMouseDragScroll(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _JourneyTimeline(
                      steps: _stepsFor(AppLocalizations.of(context)),
                      currentStep: currentStep,
                      minWidth: constraints.maxWidth,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Renders the connecting line + all step nodes.
class _JourneyTimeline extends StatelessWidget {
  final List<_JourneyStep> steps;
  final int currentStep;

  /// Width of the card's content area (measured above the scroll view),
  /// used so the timeline stretches to fill wide screens instead of
  /// always clumping at its minimum width.
  final double minWidth;

  const _JourneyTimeline({
    required this.steps,
    required this.currentStep,
    required this.minWidth,
  });

  @override
  Widget build(BuildContext context) {
    const nodeSize = AppSpacing.xl3; // node circle diameter
    const nodeGap = AppSpacing.xl5; // minimum gap between node centres
    final totalNodes = steps.length;
    // Minimum width needed so nodes/labels never collide.
    final contentWidth = nodeSize * totalNodes + nodeGap * (totalNodes - 1);
    // Fill the available width on large screens; on narrow screens fall
    // back to the minimum content width and let the enclosing
    // SingleChildScrollView handle horizontal scrolling.
    final width = contentWidth > minWidth ? contentWidth : minWidth;

    return SizedBox(
      width: width,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Connecting line (sits behind nodes)
          Positioned(
            left: nodeSize / 2,
            right: nodeSize / 2,
            child: Container(
              height: 2,
              color: AppColors.surfaceVariantLight,
            ),
          ),

          // Nodes row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(totalNodes, (i) {
              final isDone = i < currentStep;
              final isCurrent = i == currentStep;
              final isLocked = i > currentStep;
              return _StepNode(
                step: steps[i],
                isDone: isDone,
                isCurrent: isCurrent,
                isLocked: isLocked,
                nodeSize: nodeSize,
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Individual step node with label below.
class _StepNode extends StatelessWidget {
  final _JourneyStep step;
  final bool isDone;
  final bool isCurrent;
  final bool isLocked;
  final double nodeSize;

  const _StepNode({
    required this.step,
    required this.isDone,
    required this.isCurrent,
    required this.isLocked,
    required this.nodeSize,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color iconColor;
    Widget icon;

    if (isDone) {
      bgColor = AppColors.faceVerificationGreen;
      iconColor = Colors.white;
      icon = Icon(Icons.check_rounded, size: 18, color: iconColor);
    } else if (isCurrent) {
      bgColor = AppColors.primary;
      iconColor = Colors.white;
      icon = _PulsingDot();
    } else {
      bgColor = AppColors.surfaceVariantLight;
      iconColor = AppColors.textTertiaryLight;
      icon = Icon(step.icon, size: 16, color: iconColor);
    }

    return Opacity(
      opacity: isLocked ? 0.4 : 1.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: nodeSize,
            height: nodeSize,
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Center(child: icon),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: AppSpacing.xl6,
            child: Text(
              step.label,
              textAlign: TextAlign.center,
              style: AppTypography.labelSmall.copyWith(
                color: isCurrent
                    ? AppColors.primary
                    : AppColors.textSecondaryLight,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated pulsing white dot for the current step.
class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: AppSpacing.md,
        height: AppSpacing.md,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _JourneyStep {
  final String label;
  final IconData icon;
  const _JourneyStep({required this.label, required this.icon});
}
