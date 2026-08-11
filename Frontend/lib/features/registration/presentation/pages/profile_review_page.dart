import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/relationship_intelligence/horoscope_compatibility_section.dart';
import '../../../../core/widgets/relationship_intelligence/profile_prompt_section.dart';
import '../../../../core/widgets/relationship_intelligence/psychology_section.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../astro/presentation/providers/compatibility_provider.dart';
import '../../../discover/presentation/providers/discover_providers.dart';
import '../../../profile/presentation/providers/profile_dashboard_providers.dart';
import '../../../profile_completion/presentation/providers/profile_completeness_provider.dart';
import '../../../profile_photos/domain/models/user_photo.dart';
import '../../../profile_photos/presentation/providers/photo_providers.dart';
import '../../../profile_prompts/domain/models/prompt_bank_item.dart';
import '../../../profile_prompts/presentation/providers/profile_prompt_provider.dart';
import '../../../psychology/domain/models/personality_result.dart';
import '../../../psychology/presentation/providers/personality_provider.dart';
import '../../data/repositories/registration_repository.dart';
import '../../domain/models/profile_draft.dart';
import '../../domain/models/profile_flow_mode.dart';
import '../providers/registration_provider.dart';

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
  bool _isSaving = false;

  Future<void> _onEnterApp() async {
    final mode = ref.read(profileFlowModeProvider);

    // CREATE MODE: the real save now happens on the Completing screen (see
    // registration_completing_page.dart) so its checklist reflects an
    // actual in-flight finalizeToBackend() call rather than a fake loader.
    if (mode != ProfileFlowMode.edit) {
      context.go(RouteNames.registrationCompleting);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref.read(registrationProvider.notifier).finalizeToBackend();
    } on RegistrationApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).registrationSaveProfileErrorDetail(e.message))),
      );
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).registrationSaveProfileError),
        ),
      );
      return;
    }
    if (!mounted) return;

    // The edit is now persisted — refresh the dashboard's source-of-truth
    // providers so the Profile page and the Discover completeness banner
    // (both kept alive by the always-mounted Discover screen) reflect the
    // change immediately instead of a stale pre-edit snapshot.
    ref.invalidate(profileDraftResponseProvider);
    ref.invalidate(profileCompletenessSnapshotProvider);
    // discoverFeedProvider is a plain (non-autoDispose) FutureProvider kept
    // alive by the always-mounted Discover screen — without invalidating it
    // here, a user who just went from 0 rows in user_profiles to their first
    // successful finalize (e.g. the height_cm P2011 regression) would land
    // back on Discover still showing its cached "INCOMPLETE_SELF_PROFILE"
    // empty state from before this save, even though they're now eligible.
    ref.invalidate(discoverFeedProvider);

    // EDIT MODE: publish confirmation, reset to CREATE for hygiene, and
    // return to Discover — never back into onboarding/registration.
    ref.read(registrationProvider.notifier).startCreateMode();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).registrationProfileUpdated)),
    );
    context.go(RouteNames.discover);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = ref.watch(registrationProvider);
    final notifier = ref.read(registrationProvider.notifier);
    final mode = ref.watch(profileFlowModeProvider);
    final isEditMode = mode == ProfileFlowMode.edit;
    // Photos are a backend resource (PhotoController), not part of the draft —
    // read them from the single source of truth so the count/primary here
    // matches the wizard photo step and the profile dashboard exactly.
    final photos = ref.watch(myPhotosProvider).valueOrNull ?? const <UserPhoto>[];
    final hasPrimaryPhoto = photos.any((p) => p.isPrimary);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Single source of truth: the backend-computed completion (same value the
    // Profile page, Discover drawer, and completion screen show). Never a
    // locally recomputed number — that's what caused Edit Profile (57%) to
    // disagree with the Profile page (83%).
    final completion = ref.watch(backendProfileCompletionProvider).valueOrNull ?? 0;

    void editStep(int step) {
      notifier.goToStep(step);
      context.push(RouteNames.registrationWizard);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditMode ? 'Edit Profile' : l10n.registrationReviewTitle),
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
                      l10n.registrationProfileSummary,
                      style: AppTypography.headlineSmall
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 1: Basic Details ────────────────────
                    _ReviewSection(
                      title: l10n.profileBasicDetailsTitle,
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
                      title: l10n.registrationReligionTitle,
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
                      title: l10n.registrationLanguagesTitle,
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
                      title: l10n.registrationLocationTitle,
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
                      title: l10n.registrationEducationTitle,
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
                      title: l10n.registrationPhysicalTitle,
                      icon: Icons.accessibility_new_rounded,
                      stepIndex: 5,
                      isDark: isDark,
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
                      title: l10n.registrationFamilyTitle,
                      icon: Icons.family_restroom_rounded,
                      stepIndex: 7,
                      isDark: isDark,
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
                        for (var i = 0;
                            i < draft.familyDetails.siblings.length;
                            i++)
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

                    // ─── Step 10: Psychological Quiz ──────────────
                    //
                    // Reuses the same PsychologySection widget and
                    // myPersonalityResultProvider as the psychology feature
                    // and the (former edit-mode-only) Profile Intelligence
                    // block below — no separate review-row implementation.
                    Text(
                      l10n.registrationWizardQuizHeadline,
                      style: AppTypography.titleMedium
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Consumer(builder: (context, ref, _) {
                      final personalityAsync =
                          ref.watch(myPersonalityResultProvider);
                      return PsychologySection(
                        result: personalityAsync.value ??
                            const PersonalityResult(),
                        onTakeQuizTap: () async {
                          await context.push(RouteNames.psychologyQuiz);
                          ref.invalidate(myPersonalityResultProvider);
                        },
                      );
                    }),
                    const SizedBox(height: 16),

                    // ─── Step 11: Partner Preferences ─────────────
                    _ReviewSection(
                      title: l10n.registrationPartnerTitle,
                      icon: Icons.handshake_rounded,
                      stepIndex: 10,
                      isDark: isDark,
                      onEdit: () => editStep(10),
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

                    // ─── Step 12: Photos ──────────────────────────
                    _ReviewSection(
                      title: l10n.registrationPhotosTitle,
                      icon: Icons.photo_library_rounded,
                      stepIndex: 11,
                      isDark: isDark,
                      onEdit: () => editStep(11),
                      items: [
                        _ri('Primary Photo',
                            hasPrimaryPhoto ? 'Uploaded' : 'Not Uploaded'),
                        _ri('Gallery Photos', '${photos.length} photo(s)'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── Step 13: Verification ────────────────────
                    _ReviewSection(
                      title: l10n.registrationStepVerification,
                      icon: Icons.verified_rounded,
                      stepIndex: 12,
                      isDark: isDark,
                      onEdit: () => editStep(12),
                      items: [
                        _ri('Mobile', draft.verificationStatus.mobileVerified
                            ? 'Verified ✓'
                            : 'Pending'),
                        _ri('Email', draft.verificationStatus.emailVerified
                            ? 'Verified ✓'
                            : 'Pending'),
                        _ri('Income', draft.verificationStatus.incomeVerified
                            ? 'Verified ✓'
                            : 'Pending'),
                        _ri('Asset', draft.verificationStatus.assetVerified
                            ? 'Verified ✓'
                            : 'Pending'),
                        _ri('Aadhaar', draft.verificationStatus.aadhaarVerified
                            ? 'Verified ✓'
                            : 'Pending'),
                        _ri('NRI', draft.verificationStatus.nriVerified
                            ? 'Verified ✓'
                            : 'Pending'),
                      ],
                    ),
                    // ─── Profile Intelligence (EDIT MODE ONLY) ─────
                    //
                    // Registration mode already showed the personality quiz
                    // as Step 10 above. This block only covers prompts and
                    // horoscope-compatibility matching — those stay optional
                    // enrichment, added anytime from Edit Profile, never
                    // blocking a new user. Sourced entirely from independent
                    // providers (profile_prompts / astro features) — never
                    // from ProfileDraft, registrationProvider or
                    // RegistrationRepository.
                    if (isEditMode) ...[
                      const SizedBox(height: 24),
                      Text(
                        AppLocalizations.of(context).drawerProfileIntelligence,
                        style: AppTypography.headlineSmall
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(context).profileIntelReviewSubtitle,
                        style: AppTypography.bodyMedium.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Consumer(builder: (context, ref, _) {
                        final promptsAsync = ref.watch(myPromptsProvider);
                        final prompts = promptsAsync.value ?? const [];
                        return ProfilePromptSection(
                          prompts: prompts,
                          editable: true,
                          onEditTap: () async {
                            final result = await context.push<List<PromptAnswer>>(
                                RouteNames.choosePrompt,
                                extra: prompts);
                            if (result != null) {
                              await ref
                                  .read(profilePromptRepositoryProvider)
                                  .saveUserPrompts(result);
                            }
                            ref.invalidate(myPromptsProvider);
                          },
                        );
                      }),
                      const SizedBox(height: 16),
                      Consumer(builder: (context, ref, _) {
                        final horoscopeAsync =
                            ref.watch(myHoroscopeSummaryProvider);
                        final summary = horoscopeAsync.value;
                        return GestureDetector(
                          onTap: () async {
                            await context.push(RouteNames.horoscopeMatching);
                            ref.invalidate(myHoroscopeSummaryProvider);
                          },
                          child: HoroscopeCompatibilitySection(
                            rasi: summary?.rasi,
                            nakshatra: summary?.nakshatra,
                            dosham: summary?.dosham,
                            matchingEnabled: summary?.matchingEnabled ?? true,
                          ),
                        );
                      }),
                    ],
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
                label:
                    isEditMode ? 'Save Changes' : l10n.registrationContinueYourStory,
                useGoldGradient: true,
                icon: Icons.favorite_rounded,
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _onEnterApp,
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
                label: Text(AppLocalizations.of(context).registrationEditButton),
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
              AppLocalizations.of(context).registrationNoInfoYet,
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
            child: const Icon(Icons.workspace_premium_rounded,
                color: AppColors.accentGold, size: 30),
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
