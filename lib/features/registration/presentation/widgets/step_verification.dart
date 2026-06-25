import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/profile_draft.dart';

/// Step 12 — Verification Badges & Trust
class StepVerification extends StatelessWidget {
  final VerificationStatus status;
  final void Function(VerificationStatus) onChanged;

  const StepVerification({
    super.key,
    required this.status,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verification & Trust',
            style: AppTypography.headlineSmall.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Get verified badges to build trust with matches',
            style: AppTypography.bodyMedium.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 24),
          _VerificationCard(
            title: 'Mobile Number Verification',
            subtitle: 'Mandatory for contacting profiles',
            icon: Icons.phone_android_rounded,
            isVerified: true, // Automatically verified during signup/login
            isDark: isDark,
            onVerify: () {},
          ),
          const SizedBox(height: 16),
          _VerificationCard(
            title: 'Email Verification',
            subtitle: 'Receive match alerts and account updates',
            icon: Icons.email_outlined,
            isVerified: status.emailVerified,
            isDark: isDark,
            onVerify: () {
              onChanged(status.copyWith(emailVerified: true));
            },
          ),
          const SizedBox(height: 16),
          _VerificationCard(
            title: 'AI Face Selfie Verification',
            subtitle: 'Get a blue tick badge on your profile photo',
            icon: Icons.face_retouching_natural_rounded,
            isVerified: status.faceVerified,
            isDark: isDark,
            onVerify: () {
              onChanged(status.copyWith(faceVerified: true));
            },
          ),
          const SizedBox(height: 16),
          _VerificationCard(
            title: 'Government ID / Aadhaar',
            subtitle: 'Verify your age and identity securely',
            icon: Icons.verified_user_outlined,
            isVerified: status.aadhaarVerified || status.govIdVerified,
            isDark: isDark,
            onVerify: () {
              onChanged(status.copyWith(aadhaarVerified: true, govIdVerified: true));
            },
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_rounded, color: AppColors.success, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '100% Privacy Guaranteed',
                        style: AppTypography.titleSmall.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your identity documents are encrypted and never shown publicly to any user.',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isVerified;
  final bool isDark;
  final VoidCallback onVerify;

  const _VerificationCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isVerified,
    required this.isDark,
    required this.onVerify,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card(isDark: isDark).copyWith(
        border: Border.all(
          color: isVerified
              ? AppColors.success
              : (isDark ? AppColors.borderDark : AppColors.borderLight),
          width: isVerified ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isVerified
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: isVerified ? AppColors.success : AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppTypography.titleMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isVerified)
                      const Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 18),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiaryLight,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (!isVerified)
            TextButton(
              onPressed: onVerify,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('Verify', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
