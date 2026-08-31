import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/registration_provider.dart';

/// The real "creating your compatibility profile" screen shown after the
/// last wizard step, for CREATE mode only. This is the single place
/// `finalizeToBackend()` is called for the fresh-registration completion
/// path — it races the actual save against a minimum display duration so
/// the checklist never feels like a fake loader, then either advances to
/// the success screen or surfaces a real error with a retry path.
class RegistrationCompletingPage extends ConsumerStatefulWidget {
  const RegistrationCompletingPage({super.key});

  @override
  ConsumerState<RegistrationCompletingPage> createState() =>
      _RegistrationCompletingPageState();
}

class _RegistrationCompletingPageState
    extends ConsumerState<RegistrationCompletingPage> {
  static const _minDisplayDuration = Duration(seconds: 5);
  static const _stageInterval = Duration(milliseconds: 1100);

  int _visibleStages = 0;
  String? _errorMessage;
  Timer? _stageTimer;

  @override
  void initState() {
    super.initState();
    _stageTimer = Timer.periodic(_stageInterval, (timer) {
      if (!mounted) return;
      setState(() => _visibleStages = (_visibleStages + 1).clamp(0, 4));
      if (_visibleStages >= 4) timer.cancel();
    });
    _run();
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final started = DateTime.now();
    var hasError = false;
    try {
      await ref.read(registrationProvider.notifier).finalizeToBackend();
    } catch (_) {
      // Both RegistrationApiException and generic network failures show the
      // same friendly retry card — the underlying repository already logs
      // specifics for diagnosis.
      hasError = true;
    }

    final elapsed = DateTime.now().difference(started);
    final remaining = _minDisplayDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    if (!mounted) return;

    if (hasError) {
      setState(
        () => _errorMessage = AppLocalizations.of(
          context,
        ).registrationCompletingErrorMessage,
      );
      return;
    }
    context.go(RouteNames.registrationSuccess);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stages = [
      l10n.registrationCompletingStage1,
      l10n.registrationCompletingStage2,
      l10n.registrationCompletingStage3,
      l10n.registrationCompletingStage4,
    ];

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.splash),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: _errorMessage != null
                ? _buildError(context, l10n)
                : _buildChecklist(context, l10n, stages),
          ),
        ),
      ),
    );
  }

  Widget _buildChecklist(
    BuildContext context,
    AppLocalizations l10n,
    List<String> stages,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const _Sparkle(),
        const SizedBox(height: 32),
        Text(
          l10n.registrationCompletingHeadline,
          textAlign: TextAlign.center,
          style: AppTypography.headlineSmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.registrationCompletingSubtitle,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(height: 32),
        for (var i = 0; i < stages.length; i++)
          if (i < _visibleStages)
            Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.secondary,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          stages[i],
                          style: AppTypography.bodyMedium.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .animate()
                .fadeIn(duration: const Duration(milliseconds: 350))
                .slideX(
                  begin: -0.05,
                  end: 0,
                  duration: const Duration(milliseconds: 350),
                ),
      ],
    );
  }

  Widget _buildError(BuildContext context, AppLocalizations l10n) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline_rounded, color: Colors.white, size: 56),
        const SizedBox(height: 24),
        Text(
          l10n.registrationCompletingErrorTitle,
          textAlign: TextAlign.center,
          style: AppTypography.headlineSmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.registrationCompletingErrorMessage,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 32),
        NmGradientButton(
          label: l10n.registrationCompletingRetryCta,
          useAccentGradient: true,
          onPressed: () => context.go(RouteNames.profileReview),
        ),
      ],
    );
  }
}

class _Sparkle extends StatefulWidget {
  const _Sparkle();

  @override
  State<_Sparkle> createState() => _SparkleState();
}

class _SparkleState extends State<_Sparkle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(
        begin: 0.9,
        end: 1.05,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(
            color: AppColors.secondary.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        child: const Icon(
          Icons.auto_awesome_rounded,
          size: 44,
          color: AppColors.secondary,
        ),
      ),
    );
  }
}
