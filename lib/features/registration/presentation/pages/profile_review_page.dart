import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../providers/registration_provider.dart';

/// Summary review screen displayed before entering the main Home interface.
class ProfileReviewPage extends ConsumerWidget {
  const ProfileReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(registrationProvider);
    final notifier = ref.read(registrationProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Your Profile'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: AppDecorations.premiumCard,
                      child: Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.workspace_premium_rounded, color: AppColors.accentGold, size: 36),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Profile ${draft.completionPercentage.toInt()}% Ready',
                                  style: AppTypography.titleLarge.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Your luxury matrimonial journey is ready to begin.',
                                  style: AppTypography.bodySmall.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Profile Summary', style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),

                    _ReviewSection(
                      title: 'Basic Details',
                      stepIndex: 0,
                      isDark: isDark,
                      onEdit: () => _editStep(context, notifier, 0),
                      items: [
                        _ReviewItem('Name', '${draft.basicDetails.firstName} ${draft.basicDetails.lastName}'),
                        _ReviewItem('Gender', draft.basicDetails.gender),
                        _ReviewItem('Created For', draft.basicDetails.profileCreatedFor),
                        _ReviewItem('Marital Status', draft.basicDetails.maritalStatus),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _ReviewSection(
                      title: 'Religion & Community',
                      stepIndex: 1,
                      isDark: isDark,
                      onEdit: () => _editStep(context, notifier, 1),
                      items: [
                        _ReviewItem('Religion', draft.religionDetails.religion),
                        _ReviewItem('Caste', draft.religionDetails.caste),
                        _ReviewItem('Community', draft.religionDetails.community),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _ReviewSection(
                      title: 'Location & Education',
                      stepIndex: 3,
                      isDark: isDark,
                      onEdit: () => _editStep(context, notifier, 3),
                      items: [
                        _ReviewItem('Country', draft.locationDetails.country),
                        _ReviewItem('City', draft.locationDetails.city),
                        _ReviewItem('Qualification', draft.educationDetails.qualification),
                        _ReviewItem('Occupation', draft.educationDetails.occupation),
                      ],
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4)),
                ],
              ),
              child: NmGradientButton(
                label: 'Enter Nenjam Matrimony',
                useGoldGradient: true,
                icon: Icons.favorite_rounded,
                onPressed: () => context.go(RouteNames.home),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editStep(BuildContext context, RegistrationNotifier notifier, int step) {
    notifier.goToStep(step);
    context.push(RouteNames.registrationWizard);
  }
}

class _ReviewSection extends StatelessWidget {
  final String title;
  final int stepIndex;
  final bool isDark;
  final VoidCallback onEdit;
  final List<_ReviewItem> items;

  const _ReviewSection({
    required this.title,
    required this.stepIndex,
    required this.isDark,
    required this.onEdit,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(isDark: isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700)),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Edit'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary, visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          const Divider(height: 20),
          ...items.map((it) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 120, child: Text(it.label, style: AppTypography.bodySmall.copyWith(color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight))),
                    Expanded(child: Text(it.value.isEmpty ? 'Not Specified' : it.value, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600))),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _ReviewItem {
  final String label;
  final String value;
  const _ReviewItem(this.label, this.value);
}
