import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../providers/registration_provider.dart';

/// Summary review screen displaying all 12 wizard sections before entering Home.
///
/// Displays the profile completion percentage and allows editing any section
/// by jumping back to the correct wizard step.
class ProfileReviewPage extends ConsumerWidget {
  const ProfileReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(registrationProvider);
    final notifier = ref.read(registrationProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final completion = draft.completionPercentage.toInt();

    void editStep(int step) {
      notifier.goToStep(step);
      context.push(RouteNames.registrationWizard);
    }

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
                    // ─── Completion Banner ─────────────────────────
                    _CompletionBanner(completion: completion),
                    const SizedBox(height: 8),

                    // ─── Completion progress bar ───────────────────
                    LinearProgressIndicator(
                      value: completion / 100,
                      backgroundColor: isDark
                          ? AppColors.surfaceVariantDark
                          : AppColors.surfaceVariantLight,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.accentGold),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'Profile Summary',
                      style: AppTypography.headlineSmall
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 1: Basic Details ────────────────────
                    _ReviewSection(
                      title: 'Basic Details',
                      icon: Icons.person_rounded,
                      stepIndex: 0,
                      isDark: isDark,
                      onEdit: () => editStep(0),
                      items: [
                        _ri('Name',
                            '${draft.basicDetails.firstName} ${draft.basicDetails.lastName}'),
                        _ri('Gender', draft.basicDetails.gender),
                        _ri('Profile For',
                            draft.basicDetails.profileCreatedFor),
                        _ri('Marital Status', draft.basicDetails.maritalStatus),
                        _ri('Date of Birth',
                            draft.basicDetails.dob != null
                                ? '${draft.basicDetails.dob!.day}/${draft.basicDetails.dob!.month}/${draft.basicDetails.dob!.year}'
                                : ''),
                        if (draft.basicDetails.age != null)
                          _ri('Age', '${draft.basicDetails.age} years'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 2: Religion ─────────────────────────
                    _ReviewSection(
                      title: 'Religion & Community',
                      icon: Icons.temple_hindu_rounded,
                      stepIndex: 1,
                      isDark: isDark,
                      onEdit: () => editStep(1),
                      items: [
                        _ri('Religion', draft.religionDetails.religion),
                        _ri('Caste', draft.religionDetails.caste),
                        _ri('Sub Caste', draft.religionDetails.subCaste),
                        _ri('Community', draft.religionDetails.community),
                        _ri('Gothra', draft.religionDetails.gothra),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 3: Languages ────────────────────────
                    _ReviewSection(
                      title: 'Languages',
                      icon: Icons.translate_rounded,
                      stepIndex: 2,
                      isDark: isDark,
                      onEdit: () => editStep(2),
                      items: [
                        _ri('Mother Tongue',
                            draft.languageDetails.motherTongue),
                        _ri('Languages Known',
                            draft.languageDetails.languagesKnown.join(', ')),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 4: Location ─────────────────────────
                    _ReviewSection(
                      title: 'Location',
                      icon: Icons.location_on_rounded,
                      stepIndex: 3,
                      isDark: isDark,
                      onEdit: () => editStep(3),
                      items: [
                        _ri('Country', draft.locationDetails.country),
                        _ri('State', draft.locationDetails.state),
                        _ri('City', draft.locationDetails.city),
                        _ri('Area', draft.locationDetails.area),
                        _ri('PIN Code', draft.locationDetails.pinCode),
                        _ri('Native Place', draft.locationDetails.nativePlace),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 5: Education ────────────────────────
                    _ReviewSection(
                      title: 'Education & Career',
                      icon: Icons.school_rounded,
                      stepIndex: 4,
                      isDark: isDark,
                      onEdit: () => editStep(4),
                      items: [
                        _ri('Qualification',
                            draft.educationDetails.qualification),
                        _ri('College', draft.educationDetails.college),
                        _ri('Occupation', draft.educationDetails.occupation),
                        _ri('Company', draft.educationDetails.company),
                        _ri('Employment Type',
                            draft.educationDetails.employmentType),
                        _ri('Annual Income', draft.educationDetails.annualIncome),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 6: Physical ─────────────────────────
                    _ReviewSection(
                      title: 'Physical Details',
                      icon: Icons.accessibility_new_rounded,
                      stepIndex: 5,
                      isDark: isDark,
                      onEdit: () => editStep(5),
                      items: [
                        _ri('Height', draft.physicalDetails.height),
                        _ri('Weight', draft.physicalDetails.weight),
                        _ri('Body Type', draft.physicalDetails.bodyType),
                        _ri('Complexion', draft.physicalDetails.complexion),
                        _ri('Blood Group', draft.physicalDetails.bloodGroup),
                        _ri('Disability', draft.physicalDetails.disability),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 7: Lifestyle ────────────────────────
                    _ReviewSection(
                      title: 'Lifestyle',
                      icon: Icons.favorite_rounded,
                      stepIndex: 6,
                      isDark: isDark,
                      onEdit: () => editStep(6),
                      items: [
                        _ri('Diet', draft.lifestyleDetails.eatingHabit),
                        _ri('Smoking', draft.lifestyleDetails.smoking),
                        _ri('Drinking', draft.lifestyleDetails.drinking),
                        _ri('Fitness', draft.lifestyleDetails.fitness),
                        _ri('Hobbies',
                            draft.lifestyleDetails.hobbies.join(', ')),
                        _ri('About Me', draft.lifestyleDetails.aboutMe),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 8: Family ───────────────────────────
                    _ReviewSection(
                      title: 'Family Details',
                      icon: Icons.family_restroom_rounded,
                      stepIndex: 7,
                      isDark: isDark,
                      onEdit: () => editStep(7),
                      items: [
                        _ri('Father', draft.familyDetails.fatherName),
                        _ri('Father\'s Occupation',
                            draft.familyDetails.fatherOccupation),
                        _ri('Mother', draft.familyDetails.motherName),
                        _ri('Family Type', draft.familyDetails.familyType),
                        _ri('Family Values', draft.familyDetails.familyValues),
                        _ri('Family Status', draft.familyDetails.familyStatus),
                        _ri('Brothers',
                            '${draft.familyDetails.brothers}'),
                        _ri('Sisters', '${draft.familyDetails.sisters}'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 9: Horoscope ────────────────────────
                    _ReviewSection(
                      title: 'Horoscope',
                      icon: Icons.stars_rounded,
                      stepIndex: 8,
                      isDark: isDark,
                      onEdit: () => editStep(8),
                      items: [
                        _ri('Rashi', draft.horoscopeDetails.rashi),
                        _ri('Nakshatra', draft.horoscopeDetails.nakshatra),
                        _ri('Star', draft.horoscopeDetails.star),
                        _ri('Manglik', draft.horoscopeDetails.manglik),
                        _ri('Dosham', draft.horoscopeDetails.dosham),
                        _ri('Birth Place', draft.horoscopeDetails.birthPlace),
                        _ri('Birth Time', draft.horoscopeDetails.birthTime),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 10: Partner Preferences ─────────────
                    _ReviewSection(
                      title: 'Partner Preferences',
                      icon: Icons.handshake_rounded,
                      stepIndex: 9,
                      isDark: isDark,
                      onEdit: () => editStep(9),
                      items: [
                        _ri('Age Range',
                            draft.partnerPreference.preferredAgeRange),
                        _ri('Height Range',
                            draft.partnerPreference.preferredHeightRange),
                        _ri('Religion',
                            draft.partnerPreference.religionPref),
                        _ri('Caste', draft.partnerPreference.castePref),
                        _ri('Education',
                            draft.partnerPreference.educationPref),
                        _ri('Location',
                            draft.partnerPreference.locationPref),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 11: Photos ──────────────────────────
                    _ReviewSection(
                      title: 'Photos',
                      icon: Icons.photo_library_rounded,
                      stepIndex: 10,
                      isDark: isDark,
                      onEdit: () => editStep(10),
                      items: [
                        _ri('Primary Photo',
                            draft.photoGallery.primaryPhotoPath != null
                                ? 'Uploaded'
                                : 'Not Uploaded'),
                        _ri('Gallery Photos',
                            '${draft.photoGallery.galleryPaths.length} photo(s)'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 12: Verification ────────────────────
                    _ReviewSection(
                      title: 'Verification',
                      icon: Icons.verified_rounded,
                      stepIndex: 11,
                      isDark: isDark,
                      onEdit: () => editStep(11),
                      items: [
                        _ri('Mobile', draft.verificationStatus.mobileVerified
                            ? 'Verified ✓'
                            : 'Pending'),
                        _ri('Email', draft.verificationStatus.emailVerified
                            ? 'Verified ✓'
                            : 'Pending'),
                        _ri('Face', draft.verificationStatus.faceVerified
                            ? 'Verified ✓'
                            : 'Pending'),
                        _ri('Aadhaar', draft.verificationStatus.aadhaarVerified
                            ? 'Verified ✓'
                            : 'Pending'),
                      ],
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // ─── CTA ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
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

  /// Shorthand for creating a [_ReviewItem].
  _ReviewItem _ri(String label, String value) => _ReviewItem(label, value);
}

// ─── Review Section Component ────────────────────────────────────────────

class _ReviewSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final int stepIndex;
  final bool isDark;
  final VoidCallback onEdit;
  final List<_ReviewItem> items;

  const _ReviewSection({
    required this.title,
    required this.icon,
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
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.titleMedium
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, size: 14),
                label: const Text('Edit'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                  textStyle: AppTypography.labelSmall
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          ...items
              .where((it) => it.value.trim().isNotEmpty)
              .map(
                (it) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          it.label,
                          style: AppTypography.bodySmall.copyWith(
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiaryLight,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          it.value,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          if (items.every((it) => it.value.trim().isEmpty))
            Text(
              'No information added yet.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiaryLight,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Completion Banner ────────────────────────────────────────────────────

class _CompletionBanner extends StatelessWidget {
  final int completion;
  const _CompletionBanner({required this.completion});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.premiumCard,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.workspace_premium_rounded,
                color: AppColors.accentGold, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile $completion% Complete',
                  style: AppTypography.titleLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  completion >= 80
                      ? 'Excellent! Your profile is ready to find matches.'
                      : 'Complete more sections to attract better matches.',
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Review Item Model ────────────────────────────────────────────────────

class _ReviewItem {
  final String label;
  final String value;
  const _ReviewItem(this.label, this.value);
}
