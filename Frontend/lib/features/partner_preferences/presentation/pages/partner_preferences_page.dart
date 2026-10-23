import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/profile_options.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/layout/content_width.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/primary_button.dart';
import '../../../../core/widgets/cards/expandable_section.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../registration/domain/models/profile_draft.dart';
import '../../../registration/presentation/providers/registration_provider.dart';
import '../../../registration/presentation/utils/partner_preference_labels.dart';
import '../../domain/models/partner_preference_extended.dart';
import '../providers/partner_preferences_provider.dart';
import '../widgets/age_range_sheet.dart';
import '../widgets/preference_row.dart';
import '../widgets/preference_switch_row.dart';
import '../widgets/requirement_toggle.dart';

// ─── Extended-field option lists (canonical English values; only the
// on-screen label is localized via the *Map() functions below) ───────────
const List<String> _minEducationOptions = ['High School', 'Bachelors', 'Masters', 'Doctorate', 'Any'];
const List<String> _educationLevelOptions = ['High School', 'Bachelors', 'Masters', 'Doctorate', 'Professional Degree'];
// Promoted to ProfileOptions.industries so the sector a member states about
// themselves and the sector they filter partners by come from one list. Every
// value this page used to offer is still in it, so no stored preference is
// orphaned; 'Other' stays appended here because a filter may legitimately be
// left broad.
const List<String> _industryOptions = [...ProfileOptions.industries, 'Other'];
const List<String> _employmentTypeOptions = ['Salaried', 'Self-Employed', 'Business Owner', 'Not Working'];
const List<String> _countryOptions = ['India', 'USA', 'UK', 'Canada', 'Australia', 'UAE', 'Singapore', 'Other'];
const List<String> _stateOptions = ['Tamil Nadu', 'Kerala', 'Karnataka', 'Andhra Pradesh', 'Telangana', 'Maharashtra', 'Delhi', 'Other'];
const List<String> _cityOptions = ['Chennai', 'Coimbatore', 'Madurai', 'Trichy', 'Bangalore', 'Hyderabad', 'Mumbai', 'Singapore', 'USA / UK / Abroad'];
const List<String> _ethnicityOptions = ['Vellalar', 'Nadar', 'Chettiar', 'Mudaliar', 'Iyer', 'Iyengar', 'Naidu', 'Reddy', 'Other'];

Map<String, String> _mangalikMap(AppLocalizations l10n) => {
      'Must be Mangalik': l10n.partnerPrefMangalikMustBe,
      'Non-Mangalik': l10n.partnerPrefMangalikNon,
      'Doesn\'t Matter': l10n.partnerPrefDoesntMatter,
    };

Map<String, String> _dietMap(AppLocalizations l10n) => {
      'Vegetarian': l10n.partnerPrefDietVegetarian,
      'Eggetarian': l10n.partnerPrefDietEggetarian,
      'Vegan': l10n.partnerPrefDietVegan,
      'Non-Vegetarian': l10n.partnerPrefDietNonVegetarian,
      'Doesn\'t Matter': l10n.partnerPrefDoesntMatter,
    };

Map<String, String> _drinkingMap(AppLocalizations l10n) => {
      'Never': l10n.partnerPrefDrinkingNever,
      'Occasionally': l10n.partnerPrefDrinkingOccasionally,
      'Socially': l10n.partnerPrefDrinkingSocially,
      'Regularly': l10n.partnerPrefDrinkingRegularly,
      'Doesn\'t Matter': l10n.partnerPrefDoesntMatter,
    };

Map<String, String> _smokingMap(AppLocalizations l10n) => {
      'Never': l10n.partnerPrefSmokingNever,
      'Occasionally': l10n.partnerPrefSmokingOccasionally,
      'Regularly': l10n.partnerPrefSmokingRegularly,
      'Doesn\'t Matter': l10n.partnerPrefDoesntMatter,
    };

Map<String, String> _familyStatusMap(AppLocalizations l10n) => {
      'Middle Class': l10n.partnerPrefFamilyStatusMiddleClass,
      'Upper Middle Class': l10n.partnerPrefFamilyStatusUpperMiddleClass,
      'Rich': l10n.partnerPrefFamilyStatusRich,
      'Affluent': l10n.partnerPrefFamilyStatusAffluent,
    };

Map<String, String> _familyTypeMap(AppLocalizations l10n) => {
      'Joint Family': l10n.partnerPrefFamilyTypeJoint,
      'Nuclear Family': l10n.partnerPrefFamilyTypeNuclear,
    };

Map<String, String> _familyValuesMap(AppLocalizations l10n) => {
      'Traditional': l10n.partnerPrefFamilyValuesTraditional,
      'Moderate': l10n.partnerPrefFamilyValuesModerate,
      'Liberal': l10n.partnerPrefFamilyValuesLiberal,
    };

Map<String, String> _managedByMap(AppLocalizations l10n) => {
      'Self': l10n.partnerPrefManagedBySelf,
      'Parent': l10n.partnerPrefManagedByParent,
      'Sibling': l10n.partnerPrefManagedBySibling,
      'Relative': l10n.partnerPrefManagedByRelative,
      'Guardian': l10n.partnerPrefManagedByGuardian,
    };

Map<AcceptancePreference, String> _acceptanceMap(AppLocalizations l10n) => {
      AcceptancePreference.accepted: l10n.partnerPrefAcceptanceAccepted,
      AcceptancePreference.notAccepted: l10n.partnerPrefAcceptanceNotAccepted,
      AcceptancePreference.doesntMatter: l10n.partnerPrefDoesntMatter,
    };

/// Standalone, first-class Partner Preferences editor — the full
/// Jeevansathi-style field set, reachable from the Profile Drawer and the
/// Profile page's edit icon. Uses the same `PartnerPreference` domain model
/// as the registration draft (`registration/domain/models/profile_draft.dart`)
/// but has two genuinely different persisted sources for its two halves:
///
///  * The 10 **base** fields (age/height/religion/caste/education/
///    occupation/income/location/motherTongue/maritalStatus) load from and
///    save to `GET`/`PUT /discover/preferences` via
///    [partnerPreferencesProvider] — the same row the Discover/Search feed
///    filter and compatibility scorer read. This is the source of truth for
///    them; the registration draft is no longer written from this page.
///  * [PartnerPreference.extended] (religion/community, education/career,
///    family, lifestyle, location, special cases, verification — the
///    "advanced" sections below) saves to and loads from the SAME endpoint,
///    as one JSON object landing in
///    `partner_preferences.extended_preferences`. The feed reads it: diet,
///    smoking, drinking, country, ethnicity and subCaste are applied by the
///    WHERE builder, and lifestyle is scored.
///
/// It used to be otherwise — the endpoint had no `extended` field, so Save
/// persisted only the base half and the advanced edits were dropped in
/// silence. The registration draft is still what seeds the first frame (see
/// `_draft` below), but the backend is authoritative from the moment its GET
/// resolves.
///
/// Edits happen on a local draft and are only persisted when the user taps
/// Save (mirrors search_filter_sheet.dart's "edit locally, commit on
/// apply" pattern) — avoids a network call per field change.
class PartnerPreferencesPage extends ConsumerStatefulWidget {
  const PartnerPreferencesPage({super.key});

  @override
  ConsumerState<PartnerPreferencesPage> createState() => _PartnerPreferencesPageState();
}

class _PartnerPreferencesPageState extends ConsumerState<PartnerPreferencesPage> {
  // Seeded once, synchronously, from whatever the registration draft
  // already holds — this is what gives `extended` (and a placeholder value
  // for the base fields) something valid to render on the very first frame,
  // before the backend GET below resolves. `_hydratedBaseFromBackend` then
  // gates a ONE-TIME overlay of the base fields once the real saved values
  // arrive — see the `ref.listen` in `build()`. Never re-seeded after that:
  // a later rebuild of `partnerPreferencesProvider` (e.g. a background
  // refresh) must not overwrite whatever the user is mid-way through
  // editing.
  late PartnerPreference _draft = ref.read(registrationProvider).partnerPreference;
  bool _hydratedBaseFromBackend = false;
  bool _saving = false;

  PartnerPreferenceExtended get _ext => _draft.extended;

  void _updateBase(PartnerPreference Function(PartnerPreference) update) {
    setState(() => _draft = update(_draft));
  }

  void _updateExt(PartnerPreferenceExtended Function(PartnerPreferenceExtended) update) {
    setState(() => _draft = _draft.copyWith(extended: update(_ext)));
  }

  // ─── Generic pickers ────────────────────────────────────────────────

  Future<void> _pickSingle({
    required String title,
    required List<String> options,
    required String current,
    required void Function(String) apply,
    bool searchable = false,
  }) async {
    final selectedValue = current.isEmpty ? null : current;
    final future = searchable
        ? AppSheets.showSearchableSelection(context, title: title, options: options, selectedValue: selectedValue)
        : AppSheets.showSelection(context, title: title, options: options, selectedValue: selectedValue);
    final result = await future;
    if (result != null) apply(result);
  }

  Future<void> _pickMapped({
    required String title,
    required Map<String, String> valueToLabel,
    required String current,
    required void Function(String) apply,
  }) async {
    final selectedLabel = current.isEmpty ? null : valueToLabel[current];
    final result = await AppSheets.showSelection(context, title: title, options: valueToLabel.values.toList(), selectedValue: selectedLabel);
    if (result == null) return;
    final picked = valueToLabel.entries.firstWhere((e) => e.value == result).key;
    apply(picked);
  }

  Future<void> _pickAcceptance({
    required String title,
    required AcceptancePreference current,
    required void Function(AcceptancePreference) apply,
  }) async {
    final l10n = AppLocalizations.of(context);
    final map = _acceptanceMap(l10n);
    final result = await AppSheets.showSelection(context, title: title, options: map.values.toList(), selectedValue: map[current]);
    if (result == null) return;
    apply(map.entries.firstWhere((e) => e.value == result).key);
  }

  Future<void> _pickMulti({
    required String title,
    required List<String> options,
    required List<String> current,
    required void Function(List<String>) apply,
  }) async {
    final result = await AppSheets.showMultiSelection(context, title: title, options: options, selectedValues: current);
    if (result != null) apply(result);
  }

  Future<void> _pickText({
    required String title,
    required String current,
    required void Function(String) apply,
  }) async {
    final result = await AppSheets.showTextInput(context, title: title, initialValue: current);
    if (result != null) apply(result);
  }

  Future<void> _pickAgeRange({required String title, required String current, required void Function(String) apply}) async {
    final result = await showAgeRangeSheet(context, currentValue: current, title: title);
    if (result != null) apply(result);
  }

  String _displayMapped(Map<String, String> valueToLabel, String value) => value.isEmpty ? '' : (valueToLabel[value] ?? value);

  // ─── Save ───────────────────────────────────────────────────────────
  //
  // PUTs the 10 base fields to /discover/preferences — see the class doc
  // comment for why `extended` is not sent. `_saving` both drives the
  // button's loading state and (being checked before the request starts)
  // stops a double-tap from firing a second PUT while the first is still in
  // flight; PartnerPreferencesNotifier.save() guards the same thing at the
  // provider level in case some other caller ever triggers a save
  // concurrently.

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final saved =
          await ref.read(partnerPreferencesProvider.notifier).save(_draft);
      if (!mounted) return;
      // Adopt the server's response wholesale as the new baseline — a value
      // clamped to the DTO's min/max would otherwise silently diverge from
      // what the form shows. `extended` comes back from the same write now,
      // so re-merging the local copy here would discard what the backend just
      // confirmed it stored.
      setState(() => _draft = saved);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.partnerPrefSavedSnackbar)));
    } on ApiException catch (e) {
      if (!mounted) return;
      // A 400 carries the backend's own validation message (e.g. an
      // out-of-range height); anything else falls back to the generic copy.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.statusCode == 400 ? e.message : l10n.partnerPrefSaveErrorSnackbar,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.partnerPrefSaveErrorSnackbar)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // One-time overlay: the moment the real saved base-field values arrive,
    // merge them into `_draft` (keeping whatever `extended`/other base edits
    // are already there) and never do it again for this page instance —
    // exactly what `_hydratedBaseFromBackend` gates. A later emission (a
    // background `retry()`, for instance) is deliberately ignored here so it
    // can never clobber an in-progress edit; see the field's doc comment.
    ref.listen<AsyncValue<PartnerPreference>>(partnerPreferencesProvider,
        (previous, next) {
      if (_hydratedBaseFromBackend) return;
      final saved = next.valueOrNull;
      if (saved == null) return;
      _hydratedBaseFromBackend = true;
      // Both halves come from the backend now, so the draft-seeded values
      // (base placeholders AND advanced) give way to what is actually saved.
      setState(() => _draft = saved);
    });
    final prefsAsync = ref.watch(partnerPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.partnerPrefPageTitle)),
      body: !_hydratedBaseFromBackend && prefsAsync.isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_hydratedBaseFromBackend && prefsAsync.hasError
              ? Center(
                  child: NmErrorWidget(
                    onRetry: () =>
                        ref.read(partnerPreferencesProvider.notifier).retry(),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildForm(context, l10n, constraints.maxWidth),
                ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.base),
        // heightFactor 1: a bar slot would otherwise give this the whole
        // screen's height and squeeze the page body out.
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: ContentWidth.form),
            child: SizedBox(
              width: double.infinity,
              child: NmPrimaryButton(
                label: l10n.partnerPrefSaveButton,
                isLoading: _saving,
                // Disabled until the real saved values have loaded once —
                // tapping Save before then would PUT the placeholder draft
                // values (from registrationProvider, not necessarily what's
                // actually saved) and could overwrite genuine preferences
                // with empty/stale ones.
                onPressed: _hydratedBaseFromBackend ? _save : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    AppLocalizations l10n,
    double availableWidth,
  ) {
    final side = NmContentWidth.sidePadding(
      availableWidth: availableWidth,
      maxWidth: ContentWidth.form,
      minPadding: AppSpacing.pagePadding.left,
    );
    return SingleChildScrollView(
        padding: AppSpacing.pagePadding.copyWith(left: side, right: side),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // What the preferences below actually DO, which the title alone
            // does not say — the reference leads with this line, and without
            // it the screen opens straight into nine collapsed accordions
            // with no statement of purpose.
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.base),
              child: Text(
                l10n.partnerPrefIntro,
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondaryLight, height: 1.45),
              ),
            ),
            NmExpandableSection(
              title: l10n.partnerPrefSectionBasic,
              initiallyExpanded: true,
              children: _basicRows(l10n),
            ),
            // The 8 sections below are `extended` fields. They save with the
            // rest now, so the notice that used to warn they did not is gone.
            NmExpandableSection(
              title: l10n.partnerPrefSectionReligionCommunity,
              children: _religionCommunityRows(l10n),
            ),
            NmExpandableSection(
              title: l10n.partnerPrefSectionEducationCareer,
              children: _educationCareerRows(l10n),
            ),
            NmExpandableSection(
              title: l10n.partnerPrefSectionFamily,
              children: _familyRows(l10n),
            ),
            NmExpandableSection(
              title: l10n.partnerPrefSectionProfile,
              children: _profileRows(l10n),
            ),
            NmExpandableSection(
              title: l10n.partnerPrefSectionLifestyle,
              children: _lifestyleRows(l10n),
            ),
            NmExpandableSection(
              title: l10n.partnerPrefSectionLocation,
              children: _locationRows(l10n),
            ),
            NmExpandableSection(
              title: l10n.partnerPrefSectionSpecialCases,
              children: _specialCaseRows(l10n),
            ),
            NmExpandableSection(
              title: l10n.partnerPrefSectionVerification,
              children: _verificationRows(l10n),
            ),
            const SizedBox(height: AppSpacing.xl2),
          ],
        ),
      );
  }

  // ─── Basic Preferences (base fields) ───────────────────────────────
  //
  // These 10 rows carry a [RequirementToggle] — the matching-engine
  // importance tag applies to the app's original, primary matching
  // criteria. Newer enrichment fields (mangalik, diet, family values, etc.)
  // don't get one, to keep the page from turning into a wall of controls.

  List<Widget> _basicRows(AppLocalizations l10n) => [
        PreferenceRow(
          label: l10n.registrationPrefAgeLabel,
          value: anyOrSelfLabel(l10n, _draft.preferredAgeRange),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickAgeRange(
            title: l10n.registrationPrefAgeLabel,
            current: _draft.preferredAgeRange,
            apply: (v) => _updateBase((p) => p.copyWith(preferredAgeRange: v)),
          ),
        ),
        _requirementRow('age'),
        PreferenceRow(
          label: l10n.registrationPrefHeightLabel,
          value: anyOrSelfLabel(l10n, _draft.preferredHeightRange),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.registrationPrefHeightLabel,
            options: partnerPrefHeightRanges,
            current: _draft.preferredHeightRange,
            apply: (v) => _updateBase((p) => p.copyWith(preferredHeightRange: v)),
          ),
        ),
        _requirementRow('height'),
        PreferenceRow(
          label: l10n.registrationPrefMaritalLabel,
          value: maritalStatusPrefLabel(l10n, _draft.maritalStatusPref),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.registrationPrefMaritalLabel,
            options: partnerPrefMaritalStatuses,
            current: _draft.maritalStatusPref,
            apply: (v) => _updateBase((p) => p.copyWith(maritalStatusPref: v)),
          ),
        ),
        _requirementRow('maritalStatus'),
        PreferenceRow(
          label: l10n.registrationPrefLocationLabel,
          value: locationPrefLabel(l10n, _draft.locationPref),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.registrationPrefLocationLabel,
            options: partnerPrefLocations,
            current: _draft.locationPref,
            apply: (v) => _updateBase((p) => p.copyWith(locationPref: v)),
          ),
        ),
        _requirementRow('location'),
      ];

  Widget _requirementRow(String key) => RequirementToggle(
        value: _ext.requirementFor(key),
        onChanged: (v) => _updateExt((e) => e.withRequirement(key, v)),
      );

  // ─── Religion & Community ───────────────────────────────────────────

  List<Widget> _religionCommunityRows(AppLocalizations l10n) => [
        PreferenceRow(
          label: l10n.registrationPrefReligionLabel,
          value: religionPrefLabel(l10n, _draft.religionPref),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.registrationPrefReligionLabel,
            options: partnerPrefReligions,
            current: _draft.religionPref,
            apply: (v) => _updateBase((p) => p.copyWith(religionPref: v)),
          ),
        ),
        _requirementRow('religion'),
        PreferenceRow(
          label: l10n.partnerPrefEthnicityLabel,
          value: _ext.ethnicity,
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.partnerPrefEthnicityLabel,
            options: _ethnicityOptions,
            current: _ext.ethnicity,
            searchable: true,
            apply: (v) => _updateExt((e) => e.copyWith(ethnicity: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.registrationPrefCasteLabel,
          value: castePrefLabel(l10n, _draft.castePref),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.registrationPrefCasteLabel,
            options: partnerPrefCastes,
            current: _draft.castePref,
            apply: (v) => _updateBase((p) => p.copyWith(castePref: v)),
          ),
        ),
        _requirementRow('caste'),
        PreferenceRow(
          label: l10n.partnerPrefSubCasteLabel,
          value: _ext.subCaste,
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickText(
            title: l10n.partnerPrefSubCasteLabel,
            current: _ext.subCaste,
            apply: (v) => _updateExt((e) => e.copyWith(subCaste: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.registrationPrefMotherTongueLabel,
          value: motherTonguePrefLabel(l10n, _draft.motherTonguePref),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.registrationPrefMotherTongueLabel,
            options: partnerPrefMotherTongues,
            current: _draft.motherTonguePref,
            apply: (v) => _updateBase((p) => p.copyWith(motherTonguePref: v)),
          ),
        ),
        _requirementRow('motherTongue'),
        PreferenceRow(
          label: l10n.partnerPrefMangalikLabel,
          value: _displayMapped(_mangalikMap(l10n), _ext.mangalikStatus),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickMapped(
            title: l10n.partnerPrefMangalikLabel,
            valueToLabel: _mangalikMap(l10n),
            current: _ext.mangalikStatus,
            apply: (v) => _updateExt((e) => e.copyWith(mangalikStatus: v)),
          ),
        ),
      ];

  // ─── Education & Career ─────────────────────────────────────────────

  List<Widget> _educationCareerRows(AppLocalizations l10n) => [
        PreferenceRow(
          label: l10n.partnerPrefMinEducationLabel,
          value: _ext.minEducation,
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.partnerPrefMinEducationLabel,
            options: _minEducationOptions,
            current: _ext.minEducation,
            apply: (v) => _updateExt((e) => e.copyWith(minEducation: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.partnerPrefEducationLevelsLabel,
          value: _ext.preferredEducationLevels.join(', '),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickMulti(
            title: l10n.partnerPrefEducationLevelsLabel,
            options: _educationLevelOptions,
            current: _ext.preferredEducationLevels,
            apply: (v) => _updateExt((e) => e.copyWith(preferredEducationLevels: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.partnerPrefCollegesLabel,
          value: _ext.preferredColleges,
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickText(
            title: l10n.partnerPrefCollegesLabel,
            current: _ext.preferredColleges,
            apply: (v) => _updateExt((e) => e.copyWith(preferredColleges: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.partnerPrefFieldOfStudyLabel,
          value: _ext.fieldOfStudy,
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickText(
            title: l10n.partnerPrefFieldOfStudyLabel,
            current: _ext.fieldOfStudy,
            apply: (v) => _updateExt((e) => e.copyWith(fieldOfStudy: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.registrationPrefOccupationLabel,
          value: occupationPrefLabel(l10n, _draft.occupationPref),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.registrationPrefOccupationLabel,
            options: partnerPrefOccupations,
            current: _draft.occupationPref,
            apply: (v) => _updateBase((p) => p.copyWith(occupationPref: v)),
          ),
        ),
        _requirementRow('occupation'),
        PreferenceRow(
          label: l10n.partnerPrefIndustryLabel,
          value: _ext.industry,
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.partnerPrefIndustryLabel,
            options: _industryOptions,
            current: _ext.industry,
            apply: (v) => _updateExt((e) => e.copyWith(industry: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.partnerPrefEmploymentTypeLabel,
          value: _ext.employmentType,
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.partnerPrefEmploymentTypeLabel,
            options: _employmentTypeOptions,
            current: _ext.employmentType,
            apply: (v) => _updateExt((e) => e.copyWith(employmentType: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.registrationPrefIncomeLabel,
          value: anyOrSelfLabel(l10n, _draft.incomePref),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.registrationPrefIncomeLabel,
            options: partnerPrefIncomes,
            current: _draft.incomePref,
            apply: (v) => _updateBase((p) => p.copyWith(incomePref: v)),
          ),
        ),
        _requirementRow('income'),
      ];

  // ─── Family ─────────────────────────────────────────────────────────

  List<Widget> _familyRows(AppLocalizations l10n) => [
        PreferenceRow(
          label: l10n.partnerPrefFamilyStatusLabel,
          value: _displayMapped(_familyStatusMap(l10n), _ext.familyStatusPref),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickMapped(
            title: l10n.partnerPrefFamilyStatusLabel,
            valueToLabel: _familyStatusMap(l10n),
            current: _ext.familyStatusPref,
            apply: (v) => _updateExt((e) => e.copyWith(familyStatusPref: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.partnerPrefFamilyTypeLabel,
          value: _displayMapped(_familyTypeMap(l10n), _ext.familyTypePref),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickMapped(
            title: l10n.partnerPrefFamilyTypeLabel,
            valueToLabel: _familyTypeMap(l10n),
            current: _ext.familyTypePref,
            apply: (v) => _updateExt((e) => e.copyWith(familyTypePref: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.partnerPrefFamilyValuesLabel,
          value: _displayMapped(_familyValuesMap(l10n), _ext.familyValuesPref),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickMapped(
            title: l10n.partnerPrefFamilyValuesLabel,
            valueToLabel: _familyValuesMap(l10n),
            current: _ext.familyValuesPref,
            apply: (v) => _updateExt((e) => e.copyWith(familyValuesPref: v)),
          ),
        ),
      ];

  // ─── Profile Preferences ────────────────────────────────────────────

  List<Widget> _profileRows(AppLocalizations l10n) => [
        PreferenceRow(
          label: l10n.partnerPrefProfileManagedByLabel,
          value: _displayMapped(_managedByMap(l10n), _ext.profileManagedBy),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickMapped(
            title: l10n.partnerPrefProfileManagedByLabel,
            valueToLabel: _managedByMap(l10n),
            current: _ext.profileManagedBy,
            apply: (v) => _updateExt((e) => e.copyWith(profileManagedBy: v)),
          ),
        ),
      ];

  // ─── Lifestyle ──────────────────────────────────────────────────────

  List<Widget> _lifestyleRows(AppLocalizations l10n) => [
        PreferenceRow(
          label: l10n.partnerPrefDietLabel,
          value: _displayMapped(_dietMap(l10n), _ext.diet),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickMapped(
            title: l10n.partnerPrefDietLabel,
            valueToLabel: _dietMap(l10n),
            current: _ext.diet,
            apply: (v) => _updateExt((e) => e.copyWith(diet: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.partnerPrefDrinkingLabel,
          value: _displayMapped(_drinkingMap(l10n), _ext.drinking),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickMapped(
            title: l10n.partnerPrefDrinkingLabel,
            valueToLabel: _drinkingMap(l10n),
            current: _ext.drinking,
            apply: (v) => _updateExt((e) => e.copyWith(drinking: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.partnerPrefSmokingLabel,
          value: _displayMapped(_smokingMap(l10n), _ext.smoking),
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickMapped(
            title: l10n.partnerPrefSmokingLabel,
            valueToLabel: _smokingMap(l10n),
            current: _ext.smoking,
            apply: (v) => _updateExt((e) => e.copyWith(smoking: v)),
          ),
        ),
      ];

  // ─── Location Preferences ───────────────────────────────────────────

  List<Widget> _locationRows(AppLocalizations l10n) => [
        PreferenceRow(
          label: l10n.partnerPrefCountryLabel,
          value: _ext.country,
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.partnerPrefCountryLabel,
            options: _countryOptions,
            current: _ext.country,
            searchable: true,
            apply: (v) => _updateExt((e) => e.copyWith(country: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.partnerPrefStateLabel,
          value: _ext.state,
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.partnerPrefStateLabel,
            options: _stateOptions,
            current: _ext.state,
            searchable: true,
            apply: (v) => _updateExt((e) => e.copyWith(state: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.partnerPrefCityLabel,
          value: _ext.city,
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickSingle(
            title: l10n.partnerPrefCityLabel,
            options: _cityOptions,
            current: _ext.city,
            searchable: true,
            apply: (v) => _updateExt((e) => e.copyWith(city: v)),
          ),
        ),
        PreferenceSwitchRow(
          label: l10n.partnerPrefWillingToRelocateLabel,
          value: _ext.willingToRelocate,
          onChanged: (v) => _updateExt((e) => e.copyWith(willingToRelocate: v)),
        ),
        PreferenceSwitchRow(
          label: l10n.partnerPrefNriAcceptedLabel,
          value: _ext.nriAccepted,
          onChanged: (v) => _updateExt((e) => e.copyWith(nriAccepted: v)),
        ),
      ];

  // ─── Special Cases (optional, skippable) ───────────────────────────

  List<Widget> _specialCaseRows(AppLocalizations l10n) => [
        PreferenceRow(
          label: l10n.partnerPrefDivorcedAcceptedLabel,
          value: _acceptanceMap(l10n)[_ext.divorcedAccepted] ?? '',
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickAcceptance(
            title: l10n.partnerPrefDivorcedAcceptedLabel,
            current: _ext.divorcedAccepted,
            apply: (v) => _updateExt((e) => e.copyWith(divorcedAccepted: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.partnerPrefWidowedAcceptedLabel,
          value: _acceptanceMap(l10n)[_ext.widowedAccepted] ?? '',
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickAcceptance(
            title: l10n.partnerPrefWidowedAcceptedLabel,
            current: _ext.widowedAccepted,
            apply: (v) => _updateExt((e) => e.copyWith(widowedAccepted: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.partnerPrefAwaitingDivorceAcceptedLabel,
          value: _acceptanceMap(l10n)[_ext.awaitingDivorceAccepted] ?? '',
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickAcceptance(
            title: l10n.partnerPrefAwaitingDivorceAcceptedLabel,
            current: _ext.awaitingDivorceAccepted,
            apply: (v) => _updateExt((e) => e.copyWith(awaitingDivorceAccepted: v)),
          ),
        ),
        PreferenceRow(
          label: l10n.partnerPrefPhysicallyChallengedAcceptedLabel,
          value: _acceptanceMap(l10n)[_ext.physicallyChallengedAccepted] ?? '',
          placeholder: l10n.partnerPrefNotSetPlaceholder,
          onTap: () => _pickAcceptance(
            title: l10n.partnerPrefPhysicallyChallengedAcceptedLabel,
            current: _ext.physicallyChallengedAccepted,
            apply: (v) => _updateExt((e) => e.copyWith(physicallyChallengedAccepted: v)),
          ),
        ),
        PreferenceSwitchRow(
          label: l10n.partnerPrefAnySpecialCaseLabel,
          value: _ext.anySpecialCase,
          onChanged: (v) => _updateExt((e) => e.copyWith(anySpecialCase: v)),
        ),
      ];

  // ─── Verification / Other ───────────────────────────────────────────

  List<Widget> _verificationRows(AppLocalizations l10n) => [
        PreferenceSwitchRow(
          label: l10n.partnerPrefHoroscopeMatchRequiredLabel,
          value: _ext.horoscopeMatchRequired,
          onChanged: (v) => _updateExt((e) => e.copyWith(horoscopeMatchRequired: v)),
        ),
        PreferenceSwitchRow(
          label: l10n.partnerPrefVerifiedProfilesOnlyLabel,
          value: _ext.verifiedProfilesOnly,
          onChanged: (v) => _updateExt((e) => e.copyWith(verifiedProfilesOnly: v)),
        ),
        PreferenceSwitchRow(
          label: l10n.partnerPrefHasProfilePhotoLabel,
          value: _ext.hasProfilePhoto,
          onChanged: (v) => _updateExt((e) => e.copyWith(hasProfilePhoto: v)),
        ),
        PreferenceSwitchRow(
          label: l10n.partnerPrefHasHoroscopeLabel,
          value: _ext.hasHoroscope,
          onChanged: (v) => _updateExt((e) => e.copyWith(hasHoroscope: v)),
        ),
        PreferenceSwitchRow(
          label: l10n.partnerPrefAadhaarVerifiedLabel,
          value: _ext.aadhaarVerified,
          onChanged: (v) => _updateExt((e) => e.copyWith(aadhaarVerified: v)),
        ),
        PreferenceSwitchRow(
          label: l10n.partnerPrefPhoneVerifiedLabel,
          value: _ext.phoneVerified,
          onChanged: (v) => _updateExt((e) => e.copyWith(phoneVerified: v)),
        ),
      ];
}
