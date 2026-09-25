import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/indicators/nm_gradient_progress_bar.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/relationship_intelligence/psychology_section.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../profile/presentation/providers/profile_dashboard_providers.dart';
import '../../../profile_completion/presentation/widgets/complete_profile_section.dart';
import '../../../profile_photos/domain/models/user_photo.dart';
import '../../../profile_photos/presentation/providers/photo_providers.dart';
import '../../../psychology/presentation/providers/personality_provider.dart';
import '../../domain/models/profile_draft.dart';
import '../providers/registration_provider.dart';
import '../utils/open_edit_profile.dart';

/// Summary review screen displaying all 13 wizard sections before entering Home.
///
/// Displays the profile completion percentage and allows editing any section
/// by jumping back to the correct wizard step.
class ProfileReviewPage extends ConsumerStatefulWidget {
  const ProfileReviewPage({super.key});

  @override
  ConsumerState<ProfileReviewPage> createState() => _ProfileReviewPageState();
}

class _ProfileReviewPageState extends ConsumerState<ProfileReviewPage> {
  /// The real save happens on the Completing screen (see
  /// registration_completing_page.dart) so its checklist reflects an actual
  /// in-flight finalizeToBackend() call rather than a fake loader.
  ///
  /// This page is the end-of-registration review only. Editing an existing
  /// profile happens on Edit Profile's section list and its per-section
  /// pages, each of which saves just its own section — there is no
  /// whole-profile save here any more.
  void _onEnterApp() => context.go(RouteNames.registrationCompleting);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = ref.watch(registrationProvider);
    // Photos are a backend resource (PhotoController), not part of the draft —
    // read them from the single source of truth so the count/primary here
    // matches the wizard photo step and the profile dashboard exactly.
    final photos =
        ref.watch(myPhotosProvider).valueOrNull ?? const <UserPhoto>[];
    final hasPrimaryPhoto = photos.any((p) => p.isPrimary);
    // Single source of truth: the backend-computed completion (same value the
    // Profile page, Discover drawer, and completion screen show). Never a
    // locally recomputed number — that's what caused Edit Profile (57%) to
    // disagree with the Profile page (83%).
    final completion =
        ref.watch(backendProfileCompletionProvider).valueOrNull ?? 0;

    // Every section's Edit button opens that section's own edit page. See
    // profileSectionRoute().
    void editStep(int step) {
      context.push(profileSectionRoute(step));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.registrationReviewTitle),
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
                    NmGradientProgressBar(value: completion / 100, height: 6),
                    const SizedBox(height: 24),

                    // ─── Complete Profile ──────────────────────────
                    //
                    // The same widget, the same cards and the same
                    // navigation as Home — one component reading one backend
                    // response, so a section finished (or a card hidden) on
                    // either screen is reflected on the other rather than
                    // the two keeping separate lists in step by hand.
                    //
                    // Padding is 0 because this page already pads its scroll
                    // view by 24; the cards still scroll edge to edge.
                    const CompleteProfileSection(horizontalPadding: 0),

                    Text(
                      l10n.registrationProfileSummary,
                      style: AppTypography.headlineSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 1: Basic Details ────────────────────
                    _ReviewSection(
                      title: l10n.profileBasicDetailsTitle,
                      icon: Icons.person_rounded,
                      stepIndex: 0,
                      onEdit: () => editStep(0),
                      items: [
                        _ri(
                          'Name',
                          '${draft.basicDetails.firstName} ${draft.basicDetails.lastName}',
                        ),
                        _ri('Gender', draft.basicDetails.gender),
                        _ri(
                          'Profile For',
                          draft.basicDetails.profileCreatedFor,
                        ),
                        _ri('Marital Status', draft.basicDetails.maritalStatus),
                        _ri(
                          'Date of Birth',
                          draft.basicDetails.dob != null
                              ? '${draft.basicDetails.dob!.day}/${draft.basicDetails.dob!.month}/${draft.basicDetails.dob!.year}'
                              : '',
                        ),
                        if (draft.basicDetails.age != null)
                          _ri('Age', '${draft.basicDetails.age} years'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 2: Religion ─────────────────────────
                    _ReviewSection(
                      title: l10n.registrationReligionTitle,
                      icon: Icons.temple_hindu_rounded,
                      stepIndex: 1,
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

                    // ─── Step 4: Location ─────────────────────────
                    _ReviewSection(
                      title: l10n.registrationLocationTitle,
                      icon: Icons.location_on_rounded,
                      stepIndex: 3,
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
                      title: l10n.registrationEducationTitle,
                      icon: Icons.school_rounded,
                      stepIndex: 4,
                      onEdit: () => editStep(4),
                      items: [
                        _ri(
                          'Qualification',
                          draft.educationDetails.qualification,
                        ),
                        _ri('College', draft.educationDetails.college),
                        _ri('Occupation', draft.educationDetails.occupation),
                        _ri('Company', draft.educationDetails.company),
                        _ri(
                          'Employment Type',
                          draft.educationDetails.employmentType,
                        ),
                        _ri(
                          'Annual Income',
                          draft.educationDetails.annualIncome,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 6: Physical ─────────────────────────
                    _ReviewSection(
                      title: l10n.registrationPhysicalTitle,
                      icon: Icons.accessibility_new_rounded,
                      stepIndex: 5,
                      onEdit: () => editStep(5),
                      items: [
                        _ri('Height', draft.physicalDetails.height),
                        _ri('Weight', draft.physicalDetails.weight),
                        _ri('Blood Group', draft.physicalDetails.bloodGroup),
                        _ri('Disability', draft.physicalDetails.disability),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 7: Lifestyle ────────────────────────
                    _ReviewSection(
                      title: l10n.registrationLifestyleTitle,
                      icon: Icons.favorite_rounded,
                      stepIndex: 6,
                      onEdit: () => editStep(6),
                      items: [
                        _ri('Diet', draft.lifestyleDetails.eatingHabit),
                        _ri('Smoking', draft.lifestyleDetails.smoking),
                        _ri('Drinking', draft.lifestyleDetails.drinking),
                        _ri('Fitness', draft.lifestyleDetails.fitness),
                        _ri(
                          'Hobbies',
                          draft.lifestyleDetails.hobbies.join(', '),
                        ),
                        _ri('About Me', draft.lifestyleDetails.aboutMe),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 8: Family ───────────────────────────
                    _ReviewSection(
                      title: l10n.registrationFamilyTitle,
                      icon: Icons.family_restroom_rounded,
                      stepIndex: 7,
                      onEdit: () => editStep(7),
                      items: [
                        _ri(
                          'Father',
                          _combineMember(
                            name: draft.familyDetails.father.name,
                            age: draft.familyDetails.father.age,
                            occupation: draft.familyDetails.father.occupation,
                          ),
                        ),
                        _ri(
                          'Mother',
                          _combineMember(
                            name: draft.familyDetails.mother.name,
                            age: draft.familyDetails.mother.age,
                            occupation: draft.familyDetails.mother.occupation,
                          ),
                        ),
                        _ri('Family Type', draft.familyDetails.familyType),
                        _ri('Family Values', draft.familyDetails.familyValues),
                        _ri('Family Status', draft.familyDetails.familyStatus),
                        for (
                          var i = 0;
                          i < draft.familyDetails.siblings.length;
                          i++
                        )
                          _ri(
                            draft.familyDetails.siblings[i].relation ==
                                    SiblingRelation.brother
                                ? 'Brother ${i + 1}'
                                : 'Sister ${i + 1}',
                            _combineMember(
                              name: draft.familyDetails.siblings[i].name,
                              age: draft.familyDetails.siblings[i].age,
                              occupation:
                                  draft.familyDetails.siblings[i].occupation,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 9: Horoscope ────────────────────────
                    _ReviewSection(
                      title: l10n.registrationHoroscopeTitle,
                      icon: Icons.stars_rounded,
                      stepIndex: 8,
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

                    // ─── Step 10: Psychological Quiz ──────────────
                    //
                    // Reuses the same PsychologySection widget and
                    // myPersonalityResultProvider as the psychology feature
                    // — no separate review-row implementation.
                    Text(
                      l10n.registrationWizardQuizHeadline,
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Consumer(
                      builder: (context, ref, _) {
                        final personalityAsync = ref.watch(
                          myPersonalityResultProvider,
                        );
                        Future<void> openQuiz() async {
                          await context.push(RouteNames.psychologyQuiz);
                          ref.invalidate(myPersonalityResultProvider);
                        }

                        // Only a genuine "not taken" (404 -> null) gets the
                        // take-the-quiz prompt; a failed check gets a
                        // neutral retry. Optional either way — nothing
                        // here gates registration.
                        return personalityAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (_, __) => PsychologyStatusCheckFailed(
                            onRetry: () =>
                                ref.invalidate(myPersonalityResultProvider),
                          ),
                          data: (result) => PsychologySection(
                            result: result,
                            onTakeQuizTap: openQuiz,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 11: Partner Preferences ─────────────
                    _ReviewSection(
                      title: l10n.registrationPartnerTitle,
                      icon: Icons.handshake_rounded,
                      stepIndex: 10,
                      onEdit: () => editStep(10),
                      items: [
                        _ri(
                          'Age Range',
                          draft.partnerPreference.preferredAgeRange,
                        ),
                        _ri(
                          'Height Range',
                          draft.partnerPreference.preferredHeightRange,
                        ),
                        _ri('Religion', draft.partnerPreference.religionPref),
                        _ri('Caste', draft.partnerPreference.castePref),
                        _ri('Education', draft.partnerPreference.educationPref),
                        _ri('Location', draft.partnerPreference.locationPref),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 12: Photos ──────────────────────────
                    _ReviewSection(
                      title: l10n.registrationPhotosTitle,
                      icon: Icons.photo_library_rounded,
                      stepIndex: 11,
                      onEdit: () => editStep(11),
                      items: [
                        _ri(
                          'Primary Photo',
                          hasPrimaryPhoto ? 'Uploaded' : 'Not Uploaded',
                        ),
                        _ri('Gallery Photos', '${photos.length} photo(s)'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 13: Verification ────────────────────
                    _ReviewSection(
                      title: l10n.registrationStepVerification,
                      icon: Icons.verified_rounded,
                      stepIndex: 12,
                      onEdit: () => editStep(12),
                      items: [
                        _ri(
                          'Mobile',
                          draft.verificationStatus.mobileVerified
                              ? 'Verified ✓'
                              : 'Pending',
                        ),
                        _ri(
                          'Email',
                          draft.verificationStatus.emailVerified
                              ? 'Verified ✓'
                              : 'Pending',
                        ),
                        _ri(
                          'Income',
                          draft.verificationStatus.incomeVerified
                              ? 'Verified ✓'
                              : 'Pending',
                        ),
                        _ri(
                          'Asset',
                          draft.verificationStatus.assetVerified
                              ? 'Verified ✓'
                              : 'Pending',
                        ),
                        _ri(
                          'Aadhaar',
                          draft.verificationStatus.aadhaarVerified
                              ? 'Verified ✓'
                              : 'Pending',
                        ),
                        _ri(
                          'NRI',
                          draft.verificationStatus.nriVerified
                              ? 'Verified ✓'
                              : 'Pending',
                        ),
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
                color: AppColors.surfaceLight,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: NmGradientButton(
                label: l10n.registrationContinueYourStory,
                useAccentGradient: true,
                icon: Icons.favorite_rounded,
                onPressed: _onEnterApp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shorthand for creating a [_ReviewItem].
  _ReviewItem _ri(String label, String value) => _ReviewItem(label, value);

  /// Joins a Father/Mother/Sibling record's name, age, and occupation into a
  /// single display string, e.g. "Suresh, 58, Engineer".
  String _combineMember({
    required String name,
    required int? age,
    required String occupation,
  }) {
    final parts = [
      if (name.isNotEmpty) name,
      if (age != null) '$age',
      if (occupation.isNotEmpty) occupation,
    ];
    return parts.join(', ');
  }
}

// ─── Review Section Component ────────────────────────────────────────────

class _ReviewSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final int stepIndex;
  final VoidCallback onEdit;
  final List<_ReviewItem> items;

  const _ReviewSection({
    required this.title,
    required this.icon,
    required this.stepIndex,
    required this.onEdit,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(),
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
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded, size: 14),
                label: Text(
                  AppLocalizations.of(context).registrationEditButton,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                  textStyle: AppTypography.labelSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
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
                            color: AppColors.textTertiaryLight,
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
              AppLocalizations.of(context).registrationNoInfoYet,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiaryLight,
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
    final l10n = AppLocalizations.of(context);
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
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: AppColors.secondary,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.registrationProfileCompletePct(completion),
                  style: AppTypography.titleLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  completion >= 80
                      ? l10n.registrationCompleteExcellent
                      : l10n.registrationCompleteMore,
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
