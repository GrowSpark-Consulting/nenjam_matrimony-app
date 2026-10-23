import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_decorations.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../profile_photos/domain/models/user_photo.dart';
import '../../../profile_photos/presentation/providers/photo_providers.dart';
import '../../domain/models/profile_draft.dart';
import '../../domain/models/profile_for_relation.dart';
import '../providers/registration_provider.dart';
import 'profile_section_edit_page.dart';

/// **Edit Profile: the member's registration details, one card per section.**
///
/// A read-only summary, not a form — nothing is edited here, and there is no
/// Save. Each card lists one section's saved answers and its Edit opens that
/// section's own edit page, which saves only that section and returns here,
/// so the updated card is the first thing the member sees.
///
/// The cards are the sections the registration flow collects, in the order it
/// asks them. Family details, horoscope, partner preferences, the psychology
/// quiz and verification are separate parts of the profile with pages of
/// their own, reached from the Profile screen; they are not listed here.
/// Nor is the "Complete Your Profile" prompt: this page is the member's
/// registration details and nothing else.
class EditProfilePage extends ConsumerWidget {
  const EditProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return EditProfileDraftGate(
      title: l10n.drawerEditProfile,
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(l10n.drawerEditProfile)),
        body: const SafeArea(child: _SectionList()),
      ),
    );
  }
}

/// One card of the list: which section, how to summarise it, where it is
/// edited.
class EditProfileSection {
  const EditProfileSection({
    required this.id,
    required this.icon,
    required this.route,
  });

  /// Stable key, used for the row's `ValueKey('edit-profile-section-<id>')`.
  final String id;
  final IconData icon;

  /// The section's own edit page.
  final String route;

  /// Edit Profile's rows, in registration order.
  static const all = [
    EditProfileSection(
      id: 'basic',
      icon: Icons.person_rounded,
      route: RouteNames.basicInfoEdit,
    ),
    EditProfileSection(
      id: 'religion',
      icon: Icons.temple_hindu_rounded,
      route: RouteNames.religionCommunityEdit,
    ),
    EditProfileSection(
      id: 'location',
      icon: Icons.location_on_rounded,
      route: RouteNames.locationEdit,
    ),
    EditProfileSection(
      id: 'education',
      icon: Icons.school_rounded,
      route: RouteNames.educationWorkEdit,
    ),
    EditProfileSection(
      id: 'physical',
      icon: Icons.accessibility_new_rounded,
      route: RouteNames.physicalDetailsEdit,
    ),
    EditProfileSection(
      id: 'lifestyle',
      icon: Icons.favorite_rounded,
      route: RouteNames.lifestyleAboutEdit,
    ),
    EditProfileSection(
      id: 'photos',
      icon: Icons.photo_library_rounded,
      route: RouteNames.photosEdit,
    ),
  ];
}

class _SectionList extends ConsumerWidget {
  const _SectionList();

  String _title(AppLocalizations l10n, String id) => switch (id) {
    'basic' => l10n.profileBasicDetailsTitle,
    'religion' => l10n.registrationReligionTitle,
    'location' => l10n.registrationLocationTitle,
    'education' => l10n.registrationEducationTitle,
    'physical' => l10n.registrationPhysicalTitle,
    'lifestyle' => l10n.registrationLifestyleTitle,
    _ => l10n.registrationPhotosTitle,
  };

  static String _date(DateTime? d) => d == null
      ? ''
      : '${d.day.toString().padLeft(2, '0')}/'
            '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _gender(AppLocalizations l10n, String value) => switch (value) {
    'Male' => l10n.genderMale,
    'Female' => l10n.genderFemale,
    _ => value,
  };

  static String _profileFor(AppLocalizations l10n, String value) =>
      switch (ProfileForRelation.fromStorage(value)) {
        ProfileForRelation.myself => l10n.profileForOptionMyself,
        ProfileForRelation.son => l10n.profileForOptionSon,
        ProfileForRelation.daughter => l10n.profileForOptionDaughter,
        ProfileForRelation.brother => l10n.profileForOptionBrother,
        ProfileForRelation.sister => l10n.profileForOptionSister,
        ProfileForRelation.friend => l10n.profileForOptionFriend,
        ProfileForRelation.relative => l10n.profileForOptionRelative,
        null => value,
      };

  /// The section's saved answers as label/value rows — exactly the fields
  /// its edit page edits (the ones registration collects), so a card never
  /// shows something its Edit cannot change.
  List<(String, String)> _rows(
    AppLocalizations l10n,
    String id,
    ProfileDraft draft,
    List<UserPhoto> photos,
  ) {
    final basic = draft.basicDetails;
    final religion = draft.religionDetails;
    final location = draft.locationDetails;
    final education = draft.educationDetails;
    final lifestyle = draft.lifestyleDetails;
    return switch (id) {
      'basic' => [
        (l10n.registrationFirstNameLabel, basic.firstName),
        (l10n.registrationLastNameLabel, basic.lastName),
        (l10n.registrationDobLabel, _date(basic.dob)),
        (
          l10n.registrationProfileForLabel,
          _profileFor(l10n, basic.profileCreatedFor),
        ),
        (l10n.registrationGenderLabel, _gender(l10n, basic.gender)),
        (l10n.registrationMaritalStatusLabel, basic.maritalStatus),
      ],
      'religion' => [
        (l10n.registrationReligionLabel, religion.religion),
        (l10n.registrationCommunityLabel, religion.community),
        (l10n.profileBasicsSubCommunityLabel, religion.subCaste),
      ],
      'location' => [
        (l10n.registrationCountryLabel, location.country),
        (l10n.registrationStateLabel, location.state),
        (l10n.registrationCityLabel, location.city),
      ],
      'education' => [
        (l10n.registrationQualificationLabel, education.qualification),
        (l10n.registrationCollegeLabel, education.college),
        (l10n.registrationAnnualIncomeLabel, education.annualIncome),
        (l10n.registrationEmploymentTypeLabel, education.employmentType),
        (l10n.registrationOccupationLabel, education.occupation),
        (l10n.registrationCompanyLabel, education.company),
      ],
      'physical' => [
        (l10n.registrationHeightLabel, draft.physicalDetails.height),
      ],
      'lifestyle' => [
        (l10n.onboardingDietLabel, lifestyle.eatingHabit),
        (l10n.registrationAboutMeLabel, lifestyle.aboutMe),
      ],
      _ => [
        if (photos.isNotEmpty) ...[
          (
            l10n.registrationPrimaryPhoto,
            photos.any((p) => p.isPrimary) ? l10n.commonYes : l10n.commonNo,
          ),
          (l10n.registrationGalleryPhotos, '${photos.length}'),
        ],
      ],
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Watched, so a section saved on its edit page shows its new values the
    // moment the member lands back here.
    final draft = ref.watch(registrationProvider);
    final photos =
        ref.watch(myPhotosProvider).valueOrNull ?? const <UserPhoto>[];

    final cards = [
      for (final section in EditProfileSection.all)
        _SectionCard(
          key: ValueKey('edit-profile-section-${section.id}'),
          icon: section.icon,
          title: _title(l10n, section.id),
          rows: _rows(l10n, section.id, draft, photos),
          onEdit: () => context.push(section.route),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = NmContentWidth.sidePadding(
          availableWidth: constraints.maxWidth,
          maxWidth: ContentWidth.formWide,
          minPadding: AppSpacing.lg,
        );
        final twoColumns =
            constraints.maxWidth - side * 2 >= ContentWidth.formWide;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            side,
            AppSpacing.lg,
            side,
            AppSpacing.lg,
          ),
          children: twoColumns
              ? [
                  // Rows of two, each as tall as its taller card, so reading
                  // order stays left-to-right, top-to-bottom.
                  for (var i = 0; i < cards.length; i += 2) ...[
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: cards[i]),
                          const SizedBox(width: AppSpacing.base),
                          Expanded(
                            child: i + 1 < cards.length
                                ? cards[i + 1]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.base),
                  ],
                ]
              : [
                  for (final card in cards) ...[
                    card,
                    const SizedBox(height: AppSpacing.base),
                  ],
                ],
        );
      },
    );
  }
}

/// One section as a read-only card: icon, title and Edit on top, a divider,
/// then the saved answers as label/value rows. Empty answers are left out;
/// a section with none says so.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.rows,
    required this.onEdit,
  });

  final IconData icon;
  final String title;
  final List<(String, String)> rows;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filled = rows.where((r) => r.$2.trim().isNotEmpty).toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Ink(
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
                    label: Text(l10n.registrationEditButton),
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
              if (filled.isEmpty)
                Text(
                  l10n.registrationNoInfoYet,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiaryLight,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                for (final (label, value) in filled)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            label,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textTertiaryLight,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            value,
                            style: AppTypography.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
