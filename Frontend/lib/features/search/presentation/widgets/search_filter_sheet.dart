import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/buttons/secondary_button.dart';
import '../../../../core/widgets/chips/app_chips.dart';
import '../../../../core/widgets/inputs/app_dropdown.dart';
import '../../../../core/widgets/inputs/matrimony_selectors.dart';
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
  const SearchFilterSheet({super.key});

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.base,
                AppSpacing.base,
                AppSpacing.base,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Section(
                    title: l10n.searchFilterSectionBasic,
                    children: [
                      _AgeRangeField(
                        range: _draft.ageRange,
                        onChanged: (range) => _update((f) => f.copyWith(ageRange: range)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _CaptionedField(
                              caption: l10n.searchFilterHeightMin,
                              child: NmHeightSelector(
                                value: _draft.heightMin,
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
                              child: NmHeightSelector(
                                value: _draft.heightMax,
                                onChanged: (v) => _update(
                                  (f) => f.copyWith(heightMax: v, clearHeightMax: v == null),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _ChoiceChips(
                        label: l10n.searchFilterGender,
                        value: _draft.gender,
                        options: [l10n.searchFilterGenderMale, l10n.searchFilterGenderFemale],
                        onChanged: (v) => _update((f) => f.copyWith(gender: v, clearGender: v == null)),
                      ),
                    ],
                  ),
                  _Section(
                    title: l10n.searchFilterSectionReligion,
                    children: [
                      NmReligionSelector(
                        value: _draft.religion,
                        onChanged: (v) => _update((f) => f.copyWith(religion: v, clearReligion: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      NmCasteSelector(
                        value: _draft.caste,
                        onChanged: (v) => _update((f) => f.copyWith(caste: v, clearCaste: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      NmDropdown<String>(
                        label: l10n.searchFilterCommunity,
                        hint: l10n.searchFilterCommunity,
                        value: _draft.community,
                        items: _kCommunities
                            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                            .toList(),
                        onChanged: (v) => _update((f) => f.copyWith(community: v, clearCommunity: v == null)),
                      ),
                    ],
                  ),
                  _Section(
                    title: l10n.searchFilterSectionLocation,
                    children: [
                      NmCountryPicker(
                        value: _draft.country,
                        onChanged: (v) => _update((f) => f.copyWith(country: v, clearCountry: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      NmDropdown<String>(
                        label: l10n.searchFilterState,
                        hint: l10n.searchFilterState,
                        value: _draft.state,
                        items: _kStates.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (v) => _update((f) => f.copyWith(state: v, clearState: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      NmLocationSelector(
                        value: _draft.city,
                        onChanged: (v) => _update((f) => f.copyWith(city: v, clearCity: v == null)),
                      ),
                    ],
                  ),
                  _Section(
                    title: l10n.searchFilterSectionEducation,
                    children: [
                      NmEducationSelector(
                        value: _draft.education,
                        onChanged: (v) => _update((f) => f.copyWith(education: v, clearEducation: v == null)),
                      ),
                    ],
                  ),
                  _Section(
                    title: l10n.searchFilterSectionCareer,
                    children: [
                      NmProfessionSelector(
                        value: _draft.occupation,
                        onChanged: (v) => _update((f) => f.copyWith(occupation: v, clearOccupation: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      NmIncomeSelector(
                        value: _draft.annualIncome,
                        onChanged: (v) =>
                            _update((f) => f.copyWith(annualIncome: v, clearAnnualIncome: v == null)),
                      ),
                    ],
                  ),
                  _Section(
                    title: l10n.searchFilterSectionLifestyle,
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
                  _Section(
                    title: l10n.searchFilterSectionHoroscope,
                    children: [
                      NmDropdown<String>(
                        label: l10n.searchFilterRashi,
                        hint: l10n.searchFilterRashi,
                        value: _draft.rashi,
                        items: _kRashis.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (v) => _update((f) => f.copyWith(rashi: v, clearRashi: v == null)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      NmDropdown<String>(
                        label: l10n.searchFilterStar,
                        hint: l10n.searchFilterStar,
                        value: _draft.star,
                        items: _kStars.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
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
                  _Section(
                    title: l10n.searchFilterSectionVerification,
                    children: [
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
                  _Section(
                    title: l10n.searchFilterSectionPremium,
                    children: [
                      _ToggleChip(
                        label: l10n.searchFilterPremiumOnly,
                        value: _draft.premiumOnly,
                        onChanged: (v) => _update((f) => f.copyWith(premiumOnly: v)),
                      ),
                    ],
                  ),
                  _Section(
                    title: l10n.searchFilterSectionProfile,
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

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ...children,
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

class _AgeRangeField extends StatelessWidget {
  final RangeValues range;
  final ValueChanged<RangeValues> onChanged;

  const _AgeRangeField({required this.range, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.searchFilterAgeRange, style: AppTypography.labelMedium),
            Text(
              '${range.start.round()} – ${range.end.round()}',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.primarySurface,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withValues(alpha: 0.12),
            rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: RangeSlider(
            values: range,
            min: 18,
            max: 70,
            divisions: 52,
            labels: RangeLabels('${range.start.round()}', '${range.end.round()}'),
            onChanged: onChanged,
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.md,
        AppSpacing.base,
        AppSpacing.md + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.dividerLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: NmSecondaryButton(label: l10n.searchFilterReset, onPressed: onReset, height: 48),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 2,
            child: NmPrimaryButton(
              label: activeCount > 0
                  ? '${l10n.searchFilterApply} ($activeCount)'
                  : l10n.searchFilterApply,
              onPressed: onApply,
              height: 48,
            ),
          ),
        ],
      ),
    );
  }
}
