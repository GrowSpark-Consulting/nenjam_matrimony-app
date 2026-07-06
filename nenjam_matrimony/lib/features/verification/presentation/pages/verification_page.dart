import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/primary_button.dart';

/// Trust & Verification center screen.
class VerificationPage extends StatelessWidget {
  const VerificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Get Verified')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Icon(Icons.verified_rounded,
                    size: 72, color: AppColors.verified),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Build Trust with a\nVerified Badge',
                  style: AppTypography.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Verified profiles get 3x more match requests and higher visibility.',
                  style: AppTypography.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 40),
              const _VerifyStep(
                icon: Icons.badge_outlined,
                title: 'Government ID Proof',
                subtitle: 'Aadhaar, PAN, Passport, or Driving License',
              ),
              const SizedBox(height: 20),
              const _VerifyStep(
                icon: Icons.camera_front_outlined,
                title: 'Live Selfie Check',
                subtitle: 'Take a live selfie to match your ID photo',
              ),
              const Spacer(),
              NmPrimaryButton(
                label: 'Start Verification',
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(height: 16),
            ],
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
