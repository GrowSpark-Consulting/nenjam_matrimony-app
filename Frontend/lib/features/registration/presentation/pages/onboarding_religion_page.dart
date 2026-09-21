import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/tokens/app_radius.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../location/domain/models/location_models.dart';
import '../../../location/presentation/providers/location_providers.dart';
import '../../../religion/domain/models/religion_models.dart';
import '../../../religion/presentation/providers/religion_providers.dart';
import '../../domain/models/onboarding_forms.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_location_field.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 3 — "Your religion": religion, community, and the country the member
/// lives in. All three required.
///
/// The country is asked here rather than on the State & City step because it
/// decides whether "state" and "city" are even the right questions to ask
/// later; the two location steps together fill `LocationDetails`.
///
/// Caste and mother tongue used to sit on this screen. They now belong to the
/// "Let's build your Profile" step, which is where [ProfileBasicsForm] asks
/// and validates them — this page neither displays nor writes them. Nothing
/// about them was deleted: both are still NOT NULL on `user_profiles`, still
/// required by `isMatchableFromDraft`, still edited by the wizard's Religion
/// and Language steps, and still rendered on Discover cards and profile
/// detail. Only the onboarding screen that collects them changed.
class OnboardingReligionPage extends ConsumerStatefulWidget {
  const OnboardingReligionPage({super.key});

  @override
  ConsumerState<OnboardingReligionPage> createState() =>
      _OnboardingReligionPageState();
}

class _OnboardingReligionPageState
    extends ConsumerState<OnboardingReligionPage> {
  OnboardingReligionForm _form = const OnboardingReligionForm();

  @override
  void initState() {
    super.initState();
    // Reopen on whatever the draft already holds, so stepping back — or
    // resuming after PostAuthDestination rehydrates the draft — never blanks
    // an answer the member already gave.
    //
    // Every value is taken VERBATIM. Religion and community used to be
    // filtered through `OnboardingScaffold.restore` against the hardcoded
    // ProfileOptions lists, but all three fields now come from the backend's
    // master data, which is not loaded yet at this point — restoring against
    // a local list would blank a perfectly good stored answer while the
    // request is still in flight. `resolveStoredLocation` matches each stored
    // label to a real option once its list arrives, and shows it as the
    // member's own answer meanwhile.
    final draft = ref.read(registrationProvider);
    _form = OnboardingReligionForm(
      religion: draft.religionDetails.religion,
      religionCode: draft.religionDetails.religionCode,
      community: draft.religionDetails.community,
      communityCode: draft.religionDetails.communityCode,
      livingIn: draft.locationDetails.country,
      livingInCode: draft.locationDetails.countryCode,
      casteNoBar: draft.partnerPreference.castePref ==
          OnboardingReligionForm.casteNoBarPreference,
    );
  }

  String _label(AppLocalizations l10n, OnboardingReligionField field) =>
      switch (field) {
        OnboardingReligionField.religion => l10n.onboardingReligionLabel,
        OnboardingReligionField.community => l10n.onboardingCommunityLabel,
        OnboardingReligionField.livingIn => l10n.onboardingLivingInLabel,
      };

  /// Changing religion invalidates the community beneath it.
  ///
  /// The community is cleared unconditionally, unlike the old list-based
  /// version which kept an answer both religions happened to share. Community
  /// codes are religion-scoped (HINDU-TAMIL and MUSLIM-TAMIL are different
  /// rows even though both read "Tamil"), so carrying one across a religion
  /// change would send the server a pair it rejects. Re-picking the same
  /// religion is still a no-op — `copyWith` is only reached on a real change.
  ///
  /// Nothing else on the form is touched; the country lives on its own field.
  void _onReligionChanged(ReligionOption? option) {
    setState(() {
      _form = _form.copyWith(
        religion: option?.label ?? '',
        religionCode: option?.code ?? '',
        community: '',
        communityCode: '',
      );
    });
  }

  /// Picking a community stores both halves, like every other master-data
  /// field: the code the server validates and the label the member reads back.
  void _onCommunityChanged(ReligionOption? option) {
    setState(() {
      _form = _form.copyWith(
        community: option?.label ?? '',
        communityCode: option?.code ?? '',
      );
    });
  }

  /// Picking a country stores both halves: the code the server validates and
  /// the label the member reads back. Clearing state and city is NOT done
  /// here — it belongs to `applyOnboardingReligion`, because those two live
  /// on a later step and this screen has no business reaching into them.
  void _onCountryChanged(LocationOption? option) {
    setState(() {
      _form = _form.copyWith(
        livingIn: option?.label ?? '',
        livingInCode: option?.code ?? '',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final countries = ref.watch(countriesProvider);
    final religions = ref.watch(religionsProvider);

    // Same label-matching as the country below: a draft written before the
    // religion master data existed stores 'Hindu' with no code, so the stored
    // label is resolved against the list the API returned. Nothing is
    // invented — a label the API does not offer stays legacy text, and the
    // member re-picks.
    final religion = resolveStoredLocation(
      religions,
      _form.religionCode,
      _form.religion,
    );

    // The child level is keyed on the RESOLVED religion code, so a draft that
    // carried only a label still lists the right communities instead of
    // showing an empty dropdown until the member re-picks a religion their
    // screen is already showing them.
    //
    // Watching `communitiesProvider(code)` is also what makes a stale
    // response harmless: a slow reply for the previous religion resolves into
    // that religion's own provider, which nothing is watching any more.
    final religionCode = religion?.code ?? '';
    final communities = ref.watch(communitiesProvider(religionCode));
    final community = resolveStoredLocation(
      communities,
      _form.communityCode,
      _form.community,
    );

    // A draft saved before the master data existed carries a label and no
    // code — and `LocationDetails.country` defaults to 'India' for every new
    // draft — so the stored label is matched against the list the API
    // returned. Nothing is invented: a label the API does not offer stays
    // legacy text.
    final country = resolveStoredLocation(
      countries,
      _form.livingInCode,
      _form.livingIn,
    );

    return OnboardingStepScaffold(
      headline: l10n.onboardingReligionHeadline,
      crestIcon: Icons.groups_rounded,
      backRoute: RouteNames.onboardingNameDob,
      nextRoute: RouteNames.onboardingContact,
      isComplete: _form.isComplete,
      validationNames:
          _form.missingFields.map((f) => _label(l10n, f)).toList(),
      // Saved with the RESOLVED country, not the raw form. A draft that
      // carried only a label ('India', the default on every new draft) has
      // just been matched to a real option above; without folding that back
      // in, the code would stay empty and the State step two screens later
      // would have no country to list states for.
      onSave: () => ref.read(registrationProvider.notifier).applyOnboardingReligion(
            _form.copyWith(
              religion: religion?.label ?? _form.religion,
              religionCode: religion?.code ?? _form.religionCode,
              community: community?.label ?? _form.community,
              communityCode: community?.code ?? _form.communityCode,
              livingIn: country?.label ?? _form.livingIn,
              livingInCode: country?.code ?? _form.livingInCode,
            ),
          ),
      fields: [
        OnboardingLocationField(
          label: l10n.onboardingReligionLabel,
          hint: l10n.onboardingReligionHint,
          options: religions,
          optionsProvider: religionsProvider,
          value: religion,
          // Shown when the draft holds a religion the master data does not
          // offer, so an older answer reads as an answer rather than as an
          // empty field.
          legacyValue: religion == null ? _form.religion : '',
          isRequired: true,
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
          legacyValue: community == null ? _form.community : '',
          // Disabled until a religion is chosen: there is nothing to list yet,
          // and tapping should say so rather than open an empty sheet. A
          // religion stored as free text still counts as answered, so the
          // member can correct the community in place.
          enabled: religionCode.isNotEmpty || _form.religion.isNotEmpty,
          disabledHint: l10n.onboardingReligionHint,
          isRequired: true,
          onRetry: () => ref.invalidate(communitiesProvider(religionCode)),
          onChanged: _onCommunityChanged,
          loadingMessage: l10n.loadingCommunities,
          emptyMessage: l10n.noCommunitiesFound,
          errorMessage: l10n.couldntLoadCommunities,
        ),
        OnboardingLocationField(
          label: l10n.onboardingLivingInLabel,
          hint: l10n.onboardingLivingInHint,
          options: countries,
          optionsProvider: countriesProvider,
          value: country,
          // Shown when the draft holds a country the master data does not
          // offer, so an older answer reads as an answer rather than as an
          // empty field.
          legacyValue: country == null ? _form.livingIn : '',
          isRequired: true,
          onRetry: () => ref.invalidate(countriesProvider),
          onChanged: _onCountryChanged,
        ),
      ],
      trailing: _CasteNoBarCheckbox(
        label: l10n.profileBasicsCasteNoBar,
        value: _form.casteNoBar,
        onChanged: (v) => setState(() => _form = _form.copyWith(casteNoBar: v)),
      ),
    );
  }
}

/// Optional partner-community opt-out. Sits under Community because that is
/// the question it qualifies — the member has just said what their own
/// community is, and this says whether their partner's has to match.
class _CasteNoBarCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CasteNoBarCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: AppRadius.br12,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              // The row owns the gesture, but the box keeps a real callback
              // so assistive tech can toggle it directly.
              onChanged: (v) => onChanged(v ?? false),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs2),
                child: Text(
                  label,
                  style: AppTypography.bodySmall
                      .copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
