import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../l10n/app_localizations.dart';

/// Trust & Verification center screen.
class VerificationPage extends StatelessWidget {
  const VerificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.registrationVerificationTitle),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Center(
                  child: Icon(Icons.verified_rounded,
                      size: 72, color: AppColors.verified),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    l10n.registrationVerificationSubtitle,
                    style: AppTypography.headlineSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    l10n.registrationPrivacySubtitle,
                    style: AppTypography.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 36),
                _VerifyStep(
                  icon: Icons.badge_outlined,
                  title: l10n.registrationVerifyIdTitle,
                  subtitle: l10n.registrationVerifyIdSubtitle,
                ),
                const SizedBox(height: 20),
                _VerifyStep(
                  icon: Icons.camera_front_outlined,
                  title: l10n.registrationVerifyFaceTitle,
                  subtitle: l10n.registrationVerifyFaceSubtitle,
                ),
                const SizedBox(height: 36),
                NmPrimaryButton(
                  label: l10n.registrationVerifyButton,
                  onPressed: () => context.pop(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VerifyStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _VerifyStep({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.verified.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.verified),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.titleSmall),
              Text(subtitle, style: AppTypography.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
