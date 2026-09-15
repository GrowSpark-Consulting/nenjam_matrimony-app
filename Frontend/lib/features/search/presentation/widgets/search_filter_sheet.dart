import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/buttons/secondary_button.dart';
import '../../../../core/widgets/cards/expandable_section.dart';
import '../../../../core/widgets/chips/app_chips.dart';
import '../../../../core/widgets/inputs/range_slider.dart';
import '../../../../core/widgets/inputs/searchable_dropdown.dart';
import '../../../../core/widgets/inputs/segmented_control.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/search_filters_entity.dart';
import '../providers/search_providers.dart';

const _kCommunities = [
  'Vellalar',
  'Nadar',
  'Chettiar',
  'Mudaliar',
  'Iyer',
  'Iyengar',
  'Naidu',
  'Reddy',
  'Other',
];

const _kStates = [
  'Tamil Nadu',
  'Kerala',
  'Karnataka',
  'Andhra Pradesh',
  'Telangana',
  'Maharashtra',
  'Delhi',
  'Other',
];

// Owned here, in NmSearchableDropdown form. (These options were once shared
// with a core NmLocationSelector widget; that widget was unused and has been
// deleted, so this sheet is now the single definition.)
const _kCities = [
  'Chennai',
  'Coimbatore',
  'Madurai',
  'Trichy',
  'Bangalore',
  'Hyderabad',
  'Mumbai',
  'Singapore',
  'USA / UK / Abroad',
];

// The following lists are the single definition of these option sets —
// their values must stay in step with search_filters_entity.dart's fields,
// which carry the same strings. They live here for the same reason as
// _kCities: every dropdown-style field in this sheet uses
// NmSearchableDropdown rather than a native DropdownButtonFormField.
// That native dropdown's overlay menu is
// positioned/clipped relative to the wrong ancestor when opened from
// inside a modal bottom sheet — it can render partly off-screen or get
// clipped by the sheet's own Material boundary. NmSearchableDropdown
// sidesteps this entirely by opening its own bottom sheet (via
// AppSheets.showSearchableSelection) instead of a native overlay.
const _kReligions = ['Hindu', 'Christian', 'Muslim', 'Jain', 'Sikh', 'Buddhist', 'Inter-Religion'];

const _kCastes = [
  'Iyer',
  'Iyengar',
  'Mudaliar',
  'Pillai',
  'Chettiar',
  'Gounder',
  'Nadar',
  'Vanniyar',
  'Don\'t Wish to Specify',
];

const _kProfessions = [
  'Software Engineer',
  'Doctor',
  'IAS / IPS / Govt',
  'Business / Entrepreneur',
  'Finance / Banking',
  'Architect / Design',
  'Civil / Mechanical Engg',
];

const _kIncomes = [
  '5 - 10 Lakhs PA',
  '10 - 20 Lakhs PA',
  '20 - 50 Lakhs PA',
  '50 Lakhs - 1 Crore PA',
  '1 Crore+ PA',
  'Prefer not to say',
];

const _kHeights = [
  '5 ft 0 in (152 cm)',
  '5 ft 2 in (157 cm)',
  '5 ft 4 in (162 cm)',
  '5 ft 6 in (167 cm)',
  '5 ft 8 in (172 cm)',
  '5 ft 10 in (177 cm)',
  '6 ft 0 in (183 cm)',
  '6 ft 2 in+',
];

const _kEducations = [
  'B.E / B.Tech / M.Tech',
  'MBBS / MD / MS',
  'MBA / PGDM',
  'CA / CFA',
  'B.Sc / M.Sc',
  'Ph.D',
  'Other Bachelors / Masters',
];

const _kCountries = [
  'India (+91)',
  'United States (+1)',
  'United Kingdom (+44)',
  'Singapore (+65)',
  'UAE (+971)',
  'Malaysia (+60)',
  'Australia (+61)',
  'Canada (+1)',
];

const _kRashis = [
  'Mesha',
  'Vrishabha',
  'Mithuna',
  'Karka',
  'Simha',
  'Kanya',
  'Tula',
  'Vrischika',
  'Dhanu',
  'Makara',
  'Kumbha',
  'Meena',
];

const _kStars = [
  'Ashwini',
  'Bharani',
  'Krittika',
  'Rohini',
  'Mrigashira',
  'Ardra',
  'Punarvasu',
  'Pushya',
  'Ashlesha',
  'Magha',
  'Purva Phalguni',
  'Uttara Phalguni',
  'Hasta',
  'Chitra',
  'Swati',
  'Vishakha',
  'Anuradha',
  'Jyeshtha',
  'Mula',
  'Purva Ashadha',
  'Uttara Ashadha',
  'Shravana',
  'Dhanishta',
  'Shatabhisha',
  'Purva Bhadrapada',
  'Uttara Bhadrapada',
  'Revati',
];

/// Advanced filter sheet — presented via `AppSheets.show` (a modal bottom
/// sheet, never a route). Edits accumulate in a local draft; nothing is
/// applied to [searchFiltersProvider] until "Apply Filters" is tapped, and
/// "Reset" clears the draft without leaving the sheet.
class SearchFilterSheet extends ConsumerStatefulWidget {
  /// When set, only the section whose title equals this string starts
  /// expanded (overriding the usual Basic/Religion default) — lets a quick
  /// filter chip open the sheet with the relevant section already open.
  final String? initialExpandedSection;

  const SearchFilterSheet({super.key, this.initialExpandedSection});

  @override
  ConsumerState<SearchFilterSheet> createState() => _SearchFilterSheetState();
}

class _SearchFilterSheetState extends ConsumerState<SearchFilterSheet> {
  late SearchFilters _draft;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(searchFiltersProvider);
  }

  void _update(SearchFilters Function(SearchFilters) transform) {
    setState(() => _draft = transform(_draft));
  }

  int _count(List<bool> flags) => flags.where((f) => f).length;

  /// [defaultExpanded] is whether this section is one of the two that
  /// start open when the sheet is opened generically (no requested
  /// section); a specific [widget.initialExpandedSection] always wins.
  bool _isExpanded(String title, {required bool defaultExpanded}) =>
      widget.initialExpandedSection == null
          ? defaultExpanded
          : widget.initialExpandedSection == title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // AppSheets.show wraps this sheet in a Flexible, which already caps
    // whatever height we ask for here to what's actually left after the
    // handle bar/keyboard/safe-area — so a plain 85%-of-screen preference
    // is enough; no need to duplicate that clamping here too.
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.base,
              AppSpacing.sm,
              AppSpacing.base,
              AppSpacing.sm,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.searchFilterSheetTitle, style: AppTypography.titleLarge),
                TextButton(
                  onPressed: () => setState(() => _draft = const SearchFilters.empty()),
                  child: Text(l10n.searchFilterReset),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                0,
                AppSpacing.base,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NmExpandableSection(
                    title: l10n.searchFilterSectionBasic,
                    initiallyExpanded:
                        _isExpanded(l10n.searchFilterSectionBasic, defaultExpanded: true),
                    activeCount: _count([
                      _draft.ageRange != const RangeValues(18, 60),
                      _draft.heightMin != null,
                      _draft.heightMax != null,
                      _draft.gender != null,
                    ]),
                    children: [
                      NmRangeSlider(
                        label: l10n.searchFilterAgeRange,
                        range: _draft.ageRange,
                        min: 18,
                        max: 70,
                        divisions: 52,
                        onChanged: (range) => _update((f) => f.copyWith(ageRange: range)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _CaptionedField(
                              caption: l10n.searchFilterHeightMin,
                              child: NmSearchableDropdown(
                                hint: l10n.searchFilterHeightMin,
                                value: _draft.heightMin,
                                options: _kHeights,
                                onChanged: (v) => _update(
                                  (f) => f.copyWith(heightMin: v, clearHeightMin: v == null),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _CaptionedField(
                              caption: l10n.searchFilterHeightMax,
                              child: NmSearchableDropdown(
                                hint: l10n.searchFilterHeightMax,
                                value: _draft.heightMax,
                                options: _kHeights,
                                onChanged: (v) => _update(
                                  (f) => f.copyWith(heightMax: v, clearHeightMax: v == null),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(l10n.searchFilterGender, style: AppTypography.labelMedium),
                      const SizedBox(height: AppSpacing.sm),
                      NmSegmentedControl<String>(
                        options: [l10n.searchFilterGenderMale, l10n.searchFilterGenderFemale],
                        labelBuilder: (v) => v,
                        value: _draft.gender,
                        onChanged: (v) => _update((f) => f.copyWith(gender: v, clearGender: v == null)),
                      ),
                    ],
                  ),
                  NmExpandableSection(
                    title: l10n.searchFilterSectionReligion,
                    initiallyExpanded:
                        _isExpanded(l10n.searchFilterSectionReligion, defaultExpanded: true),
                    activeCount: _count([
                      _draft.religion != null,
                      _draft.caste != null,
                      _draft.community != null,
                    ]),
                    children: [
                      NmSearchableDropdown(
                        label: l10n.fieldReligion,
                        hint: l10n.fieldReligionHint,
                        value: _draft.religion,
                        options: _kReligions,
                        onChanged: (v) => _update((f) => f.copyWith(religion: v, clearReligion: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      NmSearchableDropdown(
                        label: l10n.fieldCasteDivision,
                        hint: l10n.fieldCasteHint,
                        value: _draft.caste,
                        options: _kCastes,
                        onChanged: (v) => _update((f) => f.copyWith(caste: v, clearCaste: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      NmSearchableDropdown(
                        label: l10n.searchFilterCommunity,
                        hint: l10n.searchFilterCommunity,
                        value: _draft.community,
                        options: _kCommunities,
                        onChanged: (v) => _update((f) => f.copyWith(community: v, clearCommunity: v == null)),
                      ),
                    ],
                  ),
                  NmExpandableSection(
                    title: l10n.searchFilterSectionLocation,
                    initiallyExpanded:
                        _isExpanded(l10n.searchFilterSectionLocation, defaultExpanded: false),
                    activeCount: _count([
                      _draft.country != null,
                      _draft.state != null,
                      _draft.city != null,
                    ]),
                    children: [
                      NmSearchableDropdown(
                        label: l10n.fieldCountry,
                        hint: l10n.fieldCountryHint,
                        value: _draft.country,
                        options: _kCountries,
                        onChanged: (v) => _update((f) => f.copyWith(country: v, clearCountry: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      NmSearchableDropdown(
                        label: l10n.searchFilterState,
                        hint: l10n.searchFilterState,
                        value: _draft.state,
                        options: _kStates,
                        onChanged: (v) => _update((f) => f.copyWith(state: v, clearState: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      NmSearchableDropdown(
                        label: l10n.fieldCurrentLocation,
                        hint: l10n.fieldLocationHint,
                        value: _draft.city,
                        options: _kCities,
                        onChanged: (v) => _update((f) => f.copyWith(city: v, clearCity: v == null)),
                      ),
                    ],
                  ),
                  NmExpandableSection(
                    title: l10n.searchFilterSectionEducation,
                    initiallyExpanded:
                        _isExpanded(l10n.searchFilterSectionEducation, defaultExpanded: false),
                    activeCount: _count([_draft.education != null]),
                    children: [
                      NmSearchableDropdown(
                        label: l10n.fieldQualification,
                        hint: l10n.fieldQualificationHint,
                        value: _draft.education,
                        options: _kEducations,
                        onChanged: (v) => _update((f) => f.copyWith(education: v, clearEducation: v == null)),
                      ),
                    ],
                  ),
                  NmExpandableSection(
                    title: l10n.searchFilterSectionCareer,
                    initiallyExpanded:
                        _isExpanded(l10n.searchFilterSectionCareer, defaultExpanded: false),
                    activeCount: _count([
                      _draft.occupation != null,
                      _draft.annualIncome != null,
                    ]),
                    children: [
                      NmSearchableDropdown(
                        label: l10n.fieldProfession,
                        hint: l10n.fieldProfessionHint,
                        value: _draft.occupation,
                        options: _kProfessions,
                        onChanged: (v) => _update((f) => f.copyWith(occupation: v, clearOccupation: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      NmSearchableDropdown(
                        label: l10n.fieldAnnualIncome,
                        hint: l10n.fieldIncomeHint,
                        value: _draft.annualIncome,
                        options: _kIncomes,
                        onChanged: (v) =>
                            _update((f) => f.copyWith(annualIncome: v, clearAnnualIncome: v == null)),
                      ),
                    ],
                  ),
                  NmExpandableSection(
                    title: l10n.searchFilterSectionLifestyle,
                    initiallyExpanded:
                        _isExpanded(l10n.searchFilterSectionLifestyle, defaultExpanded: false),
                    activeCount: _count([
                      _draft.diet != null,
                      _draft.smoking != null,
                      _draft.drinking != null,
                    ]),
                    children: [
                      _ChoiceChips(
                        label: l10n.searchFilterDiet,
                        value: _draft.diet,
                        options: const ['Vegetarian', 'Non-Vegetarian', 'Eggetarian', 'Vegan'],
                        onChanged: (v) => _update((f) => f.copyWith(diet: v, clearDiet: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ChoiceChips(
                        label: l10n.searchFilterSmoking,
                        value: _draft.smoking,
                        options: [
                          l10n.searchFilterOptionNo,
                          l10n.searchFilterOptionOccasionally,
                          l10n.searchFilterOptionYes,
                        ],
                        onChanged: (v) => _update((f) => f.copyWith(smoking: v, clearSmoking: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ChoiceChips(
                        label: l10n.searchFilterDrinking,
                        value: _draft.drinking,
                        options: [
                          l10n.searchFilterOptionNo,
                          l10n.searchFilterOptionOccasionally,
                          l10n.searchFilterOptionYes,
                        ],
                        onChanged: (v) => _update((f) => f.copyWith(drinking: v, clearDrinking: v == null)),
                      ),
                    ],
                  ),
                  NmExpandableSection(
                    title: l10n.searchFilterSectionHoroscope,
                    initiallyExpanded:
                        _isExpanded(l10n.searchFilterSectionHoroscope, defaultExpanded: false),
                    activeCount: _count([
                      _draft.rashi != null,
                      _draft.star != null,
                      _draft.horoscopeAvailable,
                    ]),
                    children: [
                      NmSearchableDropdown(
                        label: l10n.searchFilterRashi,
                        hint: l10n.searchFilterRashi,
                        value: _draft.rashi,
                        options: _kRashis,
                        onChanged: (v) => _update((f) => f.copyWith(rashi: v, clearRashi: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      NmSearchableDropdown(
                        label: l10n.searchFilterStar,
                        hint: l10n.searchFilterStar,
                        value: _draft.star,
                        options: _kStars,
                        onChanged: (v) => _update((f) => f.copyWith(star: v, clearStar: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ToggleChip(
                        label: l10n.searchFilterHoroscopeAvailable,
                        value: _draft.horoscopeAvailable,
                        onChanged: (v) => _update((f) => f.copyWith(horoscopeAvailable: v)),
                      ),
                    ],
                  ),
                  NmExpandableSection(
                    title: l10n.searchFilterSectionVerification,
                    initiallyExpanded:
                        _isExpanded(l10n.searchFilterSectionVerification, defaultExpanded: false),
                    activeCount: _count([
                      _draft.aadhaarVerified,
                      _draft.incomeVerified,
                      _draft.nriVerified,
                    ]),
                    children: [
                      _ToggleChip(
                        label: l10n.searchFilterVerifiedOnly,
                        value: _draft.aadhaarVerified && _draft.incomeVerified && _draft.nriVerified,
                        onChanged: (v) => _update(
                          (f) => f.copyWith(
                            aadhaarVerified: v,
                            incomeVerified: v,
                            nriVerified: v,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          _ToggleChip(
                            label: l10n.searchFilterAadhaarVerified,
                            value: _draft.aadhaarVerified,
                            onChanged: (v) => _update((f) => f.copyWith(aadhaarVerified: v)),
                          ),
                          _ToggleChip(
                            label: l10n.searchFilterIncomeVerified,
                            value: _draft.incomeVerified,
                            onChanged: (v) => _update((f) => f.copyWith(incomeVerified: v)),
                          ),
                          _ToggleChip(
                            label: l10n.searchFilterNriVerified,
                            value: _draft.nriVerified,
                            onChanged: (v) => _update((f) => f.copyWith(nriVerified: v)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  NmExpandableSection(
                    title: l10n.searchFilterSectionPremium,
                    initiallyExpanded:
                        _isExpanded(l10n.searchFilterSectionPremium, defaultExpanded: false),
                    activeCount: _count([_draft.premiumOnly]),
                    children: [
                      _ToggleChip(
                        label: l10n.searchFilterPremiumOnly,
                        value: _draft.premiumOnly,
                        onChanged: (v) => _update((f) => f.copyWith(premiumOnly: v)),
                      ),
                    ],
                  ),
                  NmExpandableSection(
                    title: l10n.searchFilterSectionProfile,
                    initiallyExpanded:
                        _isExpanded(l10n.searchFilterSectionProfile, defaultExpanded: false),
                    activeCount: _count([_draft.withPhoto, _draft.completedProfile]),
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          _ToggleChip(
                            label: l10n.searchFilterWithPhoto,
                            value: _draft.withPhoto,
                            onChanged: (v) => _update((f) => f.copyWith(withPhoto: v)),
                          ),
                          _ToggleChip(
                            label: l10n.searchFilterCompletedProfile,
                            value: _draft.completedProfile,
                            onChanged: (v) => _update((f) => f.copyWith(completedProfile: v)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _FilterSheetFooter(
            activeCount: _draft.activeCount,
            onReset: () => setState(() => _draft = const SearchFilters.empty()),
            onApply: () {
              ref.read(searchFiltersProvider.notifier).state = _draft;
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _CaptionedField extends StatelessWidget {
  final String caption;
  final Widget child;

  const _CaptionedField({required this.caption, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(caption, style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondaryLight)),
        const SizedBox(height: AppSpacing.xs),
        child,
      ],
    );
  }
}

/// Single-select chip group; tapping the active chip clears the selection.
class _ChoiceChips extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _ChoiceChips({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final option in options)
              NmFilterChip(
                label: option,
                isSelected: option == value,
                onSelected: (selected) => onChanged(selected ? option : null),
              ),
          ],
        ),
      ],
    );
  }
}

/// A single boolean filter rendered as one selectable chip.
class _ToggleChip extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleChip({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return NmFilterChip(label: label, isSelected: value, onSelected: onChanged);
  }
}

class _FilterSheetFooter extends StatelessWidget {
  final int activeCount;
  final VoidCallback onReset;
  final VoidCallback onApply;

  const _FilterSheetFooter({
    required this.activeCount,
    required this.onReset,
    required this.onApply,
  });

  /// Picks the fullest label that fits [maxWidth] without truncating —
  /// "Apply Filters (N)" when there's room, falling back to the shorter
  /// "Show Results (N)" on narrow buttons (small phones, or a wide Reset
  /// label in another locale eating into this button's share). Never
  /// returns something that can overflow: [NmPrimaryButton] still
  /// ellipsis-clips as a last-resort safety net if even the fallback form
  /// doesn't fit.
  String _applyLabel(BuildContext context, AppLocalizations l10n, double maxWidth) {
    final full = activeCount > 0
        ? '${l10n.searchFilterApply} ($activeCount)'
        : l10n.searchFilterApply;
    final fallback = activeCount > 0
        ? '${l10n.searchFilterShowResults} ($activeCount)'
        : l10n.searchFilterShowResults;

    // Same horizontal padding ElevatedButtonThemeData reserves (see
    // app_theme.dart) — the actual room available to the label text.
    const buttonPadding = 24 * 2;
    final painter = TextPainter(
      text: TextSpan(text: full, style: AppTypography.button),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    return painter.width <= maxWidth - buttonPadding ? full : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.base,
        AppSpacing.lg,
        AppSpacing.base + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        boxShadow: AppShadows.bottomNav,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: NmSecondaryButton(label: l10n.searchFilterReset, onPressed: onReset, height: 52),
          ),
          const SizedBox(width: AppSpacing.base),
          Expanded(
            flex: 3,
            child: LayoutBuilder(
              builder: (context, constraints) => NmPrimaryButton(
                label: _applyLabel(context, l10n, constraints.maxWidth),
                onPressed: onApply,
                height: 52,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
