import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/profile_options.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/birth_date.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../core/widgets/inputs/bio_textarea.dart';
import '../../../../core/widgets/inputs/birth_date_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../location/domain/models/location_models.dart';
import '../../../location/presentation/providers/location_providers.dart';
import '../../../religion/domain/models/religion_models.dart';
import '../../../religion/presentation/providers/religion_providers.dart';
import '../../domain/models/profile_draft.dart';
import '../../domain/models/profile_for_relation.dart';
import '../pages/create_profile_for_page.dart' show ProfileForChoicePill;
import 'onboarding_location_field.dart';
import 'onboarding_scaffold.dart';

/// The forms behind Edit Profile's per-section pages.
///
/// Each form edits exactly one draft section, and only the fields the
/// registration flow collects for it — built from the same field widgets,
/// option lists and cascade rules as the onboarding screens that ask them,
/// so a value reads and validates the same way in both places. Fields the
/// section also stores but registration does not ask (weight, gothra, PIN
/// code, ...) are not shown; they ride along untouched in the section value,
/// so saving a section never clears them.
///
/// A form holds its own state and reports every change through
/// [SectionFormChanged]: the section as it now stands, and the message of the
/// first malformed field, if any. Nothing is written anywhere until the page
/// saves, so leaving without saving has nothing to undo.
///
/// Every field is optional here — editing is not completing a registration —
/// but a malformed value (a date of birth that names no real date) blocks the
/// save. See [ProfileSectionEditPage].
typedef SectionFormChanged<T> = void Function(T value, String? error);

/// A dropdown that keeps a stored answer the option list does not carry,
/// rather than blanking it — see [OnboardingScaffold.optionsWith]. An edit
/// must never silently replace a value the member did not touch.
Widget _dropdown({
  required String label,
  required String hint,
  required String value,
  required List<String> options,
  required ValueChanged<String> onChanged,
  String? heading,
  bool showHeading = true,
}) {
  return OnboardingDropdownField(
    label: label,
    heading: heading,
    hint: hint,
    value: value,
    options: OnboardingScaffold.optionsWith(options, value),
    showHeading: showHeading,
    onChanged: (v) => onChanged(v ?? ''),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        text,
        style: AppTypography.titleMedium.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The fields of one form, evenly spaced.
class _Fields extends StatelessWidget {
  const _Fields(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.lg),
          children[i],
        ],
      ],
    );
  }
}

// ─── Basic Information ─────────────────────────────────────────────────

/// Name, date of birth, profile for, gender and marital status — what the
/// Profile For, Your Name and Marital Status steps collect onto
/// [BasicDetails].
class BasicInfoForm extends StatefulWidget {
  const BasicInfoForm({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final BasicDetails initial;
  final SectionFormChanged<BasicDetails> onChanged;

  @override
  State<BasicInfoForm> createState() => _BasicInfoFormState();
}

class _BasicInfoFormState extends State<BasicInfoForm> {
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late BirthDateInput _birthDate;
  late String _profileFor;
  late String _gender;
  late String _maritalStatus;

  @override
  void initState() {
    super.initState();
    final basic = widget.initial;
    _firstNameCtrl = TextEditingController(text: basic.firstName);
    _lastNameCtrl = TextEditingController(text: basic.lastName);
    _birthDate = BirthDateInput.fromDate(basic.dob);
    _profileFor = basic.profileCreatedFor;
    _gender = basic.gender;
    _maritalStatus = basic.maritalStatus;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final l10n = AppLocalizations.of(context);
    // Blank boxes are "not answered" and leave the stored date alone — the
    // backend keeps it either way, since an absent `dob` is not sent. Boxes
    // that name no real date are an error.
    final dob = _birthDate.isTouched ? _birthDate.date : widget.initial.dob;
    final dobInvalid = _birthDate.isTouched && dob == null;
    widget.onChanged(
      BasicDetails(
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        gender: _gender,
        dob: dob,
        maritalStatus: _maritalStatus,
        profileCreatedFor: _profileFor,
      ),
      dobInvalid ? l10n.birthDateErrorInvalid : null,
    );
  }

  void _update(VoidCallback change) {
    setState(change);
    _emit();
  }

  String _relationLabel(AppLocalizations l10n, ProfileForRelation relation) =>
      switch (relation) {
        ProfileForRelation.myself => l10n.profileForOptionMyself,
        ProfileForRelation.son => l10n.profileForOptionSon,
        ProfileForRelation.daughter => l10n.profileForOptionDaughter,
        ProfileForRelation.brother => l10n.profileForOptionBrother,
        ProfileForRelation.sister => l10n.profileForOptionSister,
        ProfileForRelation.friend => l10n.profileForOptionFriend,
        ProfileForRelation.relative => l10n.profileForOptionRelative,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _Fields([
      NmTextField(
        label: l10n.registrationFirstNameLabel,
        controller: _firstNameCtrl,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => _emit(),
      ),
      NmTextField(
        label: l10n.registrationLastNameLabel,
        controller: _lastNameCtrl,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => _emit(),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Heading(l10n.onboardingNameDobSection),
          NmBirthDateField(
            value: _birthDate,
            onChanged: (v) => _update(() => _birthDate = v),
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Heading(l10n.registrationProfileForLabel),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final relation in ProfileForRelation.values)
                ProfileForChoicePill(
                  label: _relationLabel(l10n, relation),
                  isSelected: _profileFor == relation.storageValue,
                  maxWidth: 160,
                  onTap: () =>
                      _update(() => _profileFor = relation.storageValue),
                ),
            ],
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Heading(l10n.registrationGenderLabel),
          Row(
            children: [
              for (final (i, gender) in const ['Male', 'Female'].indexed) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ProfileForChoicePill(
                    label: gender == 'Male'
                        ? l10n.genderMale
                        : l10n.genderFemale,
                    isSelected: _gender == gender,
                    onTap: () => _update(() => _gender = gender),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      _dropdown(
        label: l10n.onboardingMaritalLabel,
        hint: l10n.onboardingMaritalHint,
        value: _maritalStatus,
        options: ProfileOptions.maritalStatuses,
        onChanged: (v) => _update(() => _maritalStatus = v),
      ),
    ]);
  }
}

// ─── Religion & Community ──────────────────────────────────────────────

/// Religion, community and sub-community — what the Religion and "Let's
/// build your Profile" steps collect onto [ReligionDetails]. Religion and
/// community come from the backend's master data and carry their codes, as
/// on the onboarding Religion step.
class ReligionCommunityForm extends ConsumerStatefulWidget {
  const ReligionCommunityForm({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final ReligionDetails initial;
  final SectionFormChanged<ReligionDetails> onChanged;

  @override
  ConsumerState<ReligionCommunityForm> createState() =>
      _ReligionCommunityFormState();
}

class _ReligionCommunityFormState extends ConsumerState<ReligionCommunityForm> {
  late ReligionDetails _value;
  late final TextEditingController _subCasteCtrl;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
    _subCasteCtrl = TextEditingController(text: _value.subCaste);
  }

  @override
  void dispose() {
    _subCasteCtrl.dispose();
    super.dispose();
  }

  void _update(ReligionDetails next) {
    setState(() => _value = next);
    widget.onChanged(next, null);
  }

  /// Changing religion clears the community beneath it: community codes are
  /// religion-scoped, so carrying one across would send the server a pair it
  /// rejects. Re-picking the same religion changes nothing.
  void _onReligionChanged(ReligionOption? option) {
    final label = option?.label ?? '';
    final code = option?.code ?? '';
    if (label == _value.religion && code == _value.religionCode) return;
    _update(
      _value.copyWith(
        religion: label,
        religionCode: code,
        community: '',
        communityCode: '',
      ),
    );
  }

  void _onCommunityChanged(ReligionOption? option) {
    _update(
      _value.copyWith(
        community: option?.label ?? '',
        communityCode: option?.code ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final religions = ref.watch(religionsProvider);
    final religion = resolveStoredLocation(
      religions,
      _value.religionCode,
      _value.religion,
    );
    final religionCode = religion?.code ?? '';
    final communities = ref.watch(communitiesProvider(religionCode));
    final community = resolveStoredLocation(
      communities,
      _value.communityCode,
      _value.community,
    );

    return _Fields([
      OnboardingLocationField(
        label: l10n.onboardingReligionLabel,
        hint: l10n.onboardingReligionHint,
        options: religions,
        optionsProvider: religionsProvider,
        value: religion,
        legacyValue: religion == null ? _value.religion : '',
        onRetry: () => ref.invalidate(religionsProvider),
        onChanged: _onReligionChanged,
        loadingMessage: l10n.loadingReligions,
        emptyMessage: l10n.noReligionsAvailable,
        errorMessage: l10n.couldntLoadReligions,
      ),
      OnboardingLocationField(
        label: l10n.onboardingCommunityLabel,
        hint: l10n.onboardingCommunityHint,
        options: communities,
        optionsProvider: communitiesProvider(religionCode),
        value: community,
        legacyValue: community == null ? _value.community : '',
        enabled: religionCode.isNotEmpty || _value.religion.isNotEmpty,
        disabledHint: l10n.onboardingReligionHint,
        onRetry: () => ref.invalidate(communitiesProvider(religionCode)),
        onChanged: _onCommunityChanged,
        loadingMessage: l10n.loadingCommunities,
        emptyMessage: l10n.noCommunitiesFound,
        errorMessage: l10n.couldntLoadCommunities,
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Heading(l10n.profileBasicsSubCommunityLabel),
          NmTextField(
            label: l10n.registrationSubCasteLabel,
            hint: l10n.profileBasicsSubCommunityHint,
            controller: _subCasteCtrl,
            textCapitalization: TextCapitalization.words,
            onChanged: (v) => _update(_value.copyWith(subCaste: v.trim())),
          ),
        ],
      ),
    ]);
  }
}

// ─── Location ──────────────────────────────────────────────────────────

/// Country, state and city — what the Religion ("Living in") and "Let's
/// build your Profile" steps collect onto [LocationDetails], from the
/// location master data. Changing a parent clears what sits beneath it.
class LocationForm extends ConsumerStatefulWidget {
  const LocationForm({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final LocationDetails initial;
  final SectionFormChanged<LocationDetails> onChanged;

  @override
  ConsumerState<LocationForm> createState() => _LocationFormState();
}

class _LocationFormState extends ConsumerState<LocationForm> {
  late LocationDetails _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  void _update(LocationDetails next) {
    setState(() => _value = next);
    widget.onChanged(next, null);
  }

  void _onCountryChanged(LocationOption? option) {
    final label = option?.label ?? '';
    final code = option?.code ?? '';
    if (label == _value.country && code == _value.countryCode) return;
    _update(
      _value.copyWith(
        country: label,
        countryCode: code,
        state: '',
        stateCode: '',
        city: '',
        cityCode: '',
      ),
    );
  }

  void _onStateChanged(LocationOption? option) {
    final label = option?.label ?? '';
    final code = option?.code ?? '';
    if (label == _value.state && code == _value.stateCode) return;
    _update(
      _value.copyWith(state: label, stateCode: code, city: '', cityCode: ''),
    );
  }

  void _onCityChanged(LocationOption? option) {
    _update(
      _value.copyWith(city: option?.label ?? '', cityCode: option?.code ?? ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final countries = ref.watch(countriesProvider);
    final country = resolveStoredLocation(
      countries,
      _value.countryCode,
      _value.country,
    );
    final countryCode = country?.code ?? '';
    final states = ref.watch(statesProvider(countryCode));
    final state = resolveStoredLocation(states, _value.stateCode, _value.state);
    final stateCode = state?.code ?? '';
    final cities = ref.watch(citiesProvider(stateCode));
    final city = resolveStoredLocation(cities, _value.cityCode, _value.city);

    return _Fields([
      OnboardingLocationField(
        label: l10n.onboardingLivingInLabel,
        hint: l10n.onboardingLivingInHint,
        options: countries,
        optionsProvider: countriesProvider,
        value: country,
        legacyValue: country == null ? _value.country : '',
        onRetry: () => ref.invalidate(countriesProvider),
        onChanged: _onCountryChanged,
      ),
      OnboardingLocationField(
        label: l10n.registrationStateLabel,
        hint: l10n.profileBasicsStateHint,
        options: states,
        optionsProvider: statesProvider(countryCode),
        value: state,
        legacyValue: state == null ? _value.state : '',
        enabled: countryCode.isNotEmpty,
        disabledHint: l10n.onboardingLivingInHint,
        onRetry: () => ref.invalidate(statesProvider(countryCode)),
        onChanged: _onStateChanged,
        loadingMessage: l10n.loadingStates,
        emptyMessage: l10n.noStatesAvailable,
        errorMessage: l10n.couldntLoadStates,
      ),
      OnboardingLocationField(
        label: l10n.registrationCityLabel,
        hint: l10n.profileBasicsCityHint,
        options: cities,
        optionsProvider: citiesProvider(stateCode),
        value: city,
        legacyValue: city == null ? _value.city : '',
        enabled: stateCode.isNotEmpty,
        disabledHint: l10n.profileBasicsStateHint,
        onRetry: () => ref.invalidate(citiesProvider(stateCode)),
        onChanged: _onCityChanged,
        loadingMessage: l10n.findingCitiesIn(state?.label ?? _value.state),
        emptyMessage: l10n.noCitiesFoundForState,
        errorMessage: l10n.couldntLoadCities,
      ),
    ]);
  }
}

// ─── Education & Work ──────────────────────────────────────────────────

/// Qualification and college (the Education step), then income and work
/// (the Income step) — all on [EducationDetails].
class EducationWorkForm extends StatefulWidget {
  const EducationWorkForm({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final EducationDetails initial;
  final SectionFormChanged<EducationDetails> onChanged;

  @override
  State<EducationWorkForm> createState() => _EducationWorkFormState();
}

class _EducationWorkFormState extends State<EducationWorkForm> {
  late EducationDetails _value;
  late final TextEditingController _collegeCtrl;
  late final TextEditingController _companyCtrl;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
    _collegeCtrl = TextEditingController(text: _value.college);
    _companyCtrl = TextEditingController(text: _value.company);
  }

  @override
  void dispose() {
    _collegeCtrl.dispose();
    _companyCtrl.dispose();
    super.dispose();
  }

  void _update(EducationDetails next) {
    setState(() => _value = next);
    widget.onChanged(next, null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _Fields([
      _dropdown(
        label: l10n.onboardingQualificationLabel,
        hint: l10n.onboardingQualificationHint,
        value: _value.qualification,
        options: ProfileOptions.qualifications,
        onChanged: (v) => _update(_value.copyWith(qualification: v)),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Heading(l10n.onboardingCollegeLabel),
          NmTextField(
            label: l10n.onboardingCollegeFieldLabel,
            hint: l10n.onboardingCollegeHint,
            controller: _collegeCtrl,
            onChanged: (v) => _update(_value.copyWith(college: v.trim())),
          ),
        ],
      ),
      _dropdown(
        label: l10n.onboardingIncomeLabel,
        hint: l10n.onboardingIncomeHint,
        value: _value.annualIncome,
        options: ProfileOptions.incomeRanges,
        onChanged: (v) => _update(_value.copyWith(annualIncome: v)),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Heading(l10n.onboardingWorkHeadline),
          _dropdown(
            label: l10n.onboardingWorkWithLabel,
            hint: l10n.onboardingWorkWithHint,
            value: _value.employmentType,
            options: ProfileOptions.employmentTypes,
            showHeading: false,
            onChanged: (v) => _update(_value.copyWith(employmentType: v)),
          ),
          const SizedBox(height: AppSpacing.base),
          _dropdown(
            label: l10n.onboardingWorkAsLabel,
            hint: l10n.onboardingWorkAsHint,
            value: _value.occupation,
            options: ProfileOptions.occupations,
            showHeading: false,
            onChanged: (v) => _update(_value.copyWith(occupation: v)),
          ),
          const SizedBox(height: AppSpacing.base),
          NmTextField(
            label: l10n.onboardingCompanyLabel,
            hint: l10n.onboardingCompanyHint,
            controller: _companyCtrl,
            textInputAction: TextInputAction.done,
            onChanged: (v) => _update(_value.copyWith(company: v.trim())),
          ),
        ],
      ),
    ]);
  }
}

// ─── Physical Details ──────────────────────────────────────────────────

/// Height — the one physical detail registration asks (on the Marital
/// Status step), on [PhysicalDetails].
class PhysicalDetailsForm extends StatefulWidget {
  const PhysicalDetailsForm({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final PhysicalDetails initial;
  final SectionFormChanged<PhysicalDetails> onChanged;

  @override
  State<PhysicalDetailsForm> createState() => _PhysicalDetailsFormState();
}

class _PhysicalDetailsFormState extends State<PhysicalDetailsForm> {
  late PhysicalDetails _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _Fields([
      _dropdown(
        heading: l10n.onboardingHeightLabel,
        label: l10n.onboardingHeightFieldLabel,
        hint: l10n.onboardingHeightHint,
        value: _value.height,
        options: ProfileOptions.heights,
        onChanged: (v) {
          final next = _value.copyWith(height: v);
          setState(() => _value = next);
          widget.onChanged(next, null);
        },
      ),
    ]);
  }
}

// ─── Lifestyle & About ─────────────────────────────────────────────────

/// Diet (the Marital Status step) and About Me (the About step), on
/// [LifestyleDetails].
class LifestyleAboutForm extends StatefulWidget {
  const LifestyleAboutForm({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final LifestyleDetails initial;
  final SectionFormChanged<LifestyleDetails> onChanged;

  @override
  State<LifestyleAboutForm> createState() => _LifestyleAboutFormState();
}

class _LifestyleAboutFormState extends State<LifestyleAboutForm> {
  late LifestyleDetails _value;
  late final TextEditingController _aboutCtrl;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
    _aboutCtrl = TextEditingController(text: _value.aboutMe);
  }

  @override
  void dispose() {
    _aboutCtrl.dispose();
    super.dispose();
  }

  void _update(LifestyleDetails next) {
    setState(() => _value = next);
    widget.onChanged(next, null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _Fields([
      _dropdown(
        heading: l10n.onboardingDietLabel,
        label: l10n.onboardingDietFieldLabel,
        hint: l10n.onboardingDietHint,
        value: _value.eatingHabit,
        options: ProfileOptions.diets,
        onChanged: (v) => _update(_value.copyWith(eatingHabit: v)),
      ),
      NmBioTextArea(
        controller: _aboutCtrl,
        label: l10n.onboardingAboutHeadline,
        onChanged: (v) => _update(_value.copyWith(aboutMe: v.trim())),
      ),
    ]);
  }
}
