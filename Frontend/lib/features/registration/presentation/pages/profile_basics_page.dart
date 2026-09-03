import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/profile_options.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/onboarding_forms.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 5 — "Now let's build your Profile": State, City and Sub-community.
///
/// Gender moved to [CreateProfileForPage], which asks it first. Caste and
/// mother tongue are not collected in onboarding at all — see
/// [ProfileBasicsForm] for what that means for the profile write, which is
/// the one consequence worth knowing before adding a field back.
///
/// Sub-community stays optional: `sub_caste` is nullable and the gate in
/// [PostAuthDestination] does not test it, so requiring it here would block a
/// member on a field the router will happily wave them past.
class ProfileBasicsPage extends ConsumerStatefulWidget {
  const ProfileBasicsPage({super.key});

  @override
  ConsumerState<ProfileBasicsPage> createState() => _ProfileBasicsPageState();
}

class _ProfileBasicsPageState extends ConsumerState<ProfileBasicsPage> {
  ProfileBasicsForm _form = const ProfileBasicsForm();

  final _subCommunityCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Restored verbatim, NOT filtered through OnboardingScaffold.restore.
    // The state/city lists are a curated subset, and real profiles hold
    // answers outside it, so filtering blanked a stored answer and the next
    // save overwrote it. The dropdowns below widen their options to include
    // whatever was stored — see OnboardingScaffold.optionsWith.
    final draft = ref.read(registrationProvider);
    final location = draft.locationDetails;
    _subCommunityCtrl.text = draft.religionDetails.subCaste;
    _form = ProfileBasicsForm(
      state: location.state,
      city: location.city,
      // Verbatim: free text, so there is no list to filter against.
      subCommunity: draft.religionDetails.subCaste,
    );
  }

  @override
  void dispose() {
    _subCommunityCtrl.dispose();
    super.dispose();
  }

  String _fieldLabel(AppLocalizations l10n, ProfileBasicsField field) =>
      switch (field) {
        ProfileBasicsField.state => l10n.registrationStateLabel,
        ProfileBasicsField.city => l10n.registrationCityLabel,
      };

  /// Changing state re-scopes the city list. The current answer is cleared
  /// only when the new list no longer offers it, so correcting a typo'd
  /// state does not silently discard a city that is still valid.
  void _onStateChanged(String state) {
    // Re-picking the state already selected changes nothing, so it must not
    // cost the member their city. That matters now that a stored city outside
    // the curated list survives rehydration: someone who saved "Bengaluru"
    // and re-opened the step would lose it simply by tapping their own state,
    // because the list for Karnataka offers "Bangalore" and not "Bengaluru".
    if (state == _form.state) return;

    setState(() {
      final stillValid = ProfileOptions.citiesFor(state).contains(_form.city);
      _form = _form.copyWith(state: state, city: stillValid ? _form.city : '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return OnboardingStepScaffold(
      headline: l10n.profileBasicsHeadline,
      crestIcon: Icons.place_rounded,
      backRoute: RouteNames.onboardingContact,
      nextRoute: RouteNames.onboardingMarital,
      isComplete: _form.isComplete,
      validationNames:
          _form.missingFields.map((f) => _fieldLabel(l10n, f)).toList(),
      onSave: () =>
          ref.read(registrationProvider.notifier).applyProfileBasics(_form),
      fields: [
        OnboardingDropdownField(
          label: l10n.registrationStateLabel,
          hint: l10n.profileBasicsStateHint,
          value: _form.state,
          options: OnboardingScaffold.optionsWith(
            ProfileOptions.states,
            _form.state,
          ),
          isRequired: true,
          onChanged: (v) => _onStateChanged(v ?? ''),
        ),
        OnboardingDropdownField(
          label: l10n.registrationCityLabel,
          hint: l10n.profileBasicsCityHint,
          value: _form.city,
          options: OnboardingScaffold.optionsWith(
            ProfileOptions.citiesFor(_form.state),
            _form.city,
          ),
          isRequired: true,
          onChanged: (v) =>
              setState(() => _form = _form.copyWith(city: v ?? '')),
        ),
        // Free text, like the wizard's own sub-caste field: there is no
        // authoritative list in this app, and inventing one is not an option.
        // Optional — see the class doc — so it carries no asterisk and no
        // entry in [missingFields].
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.profileBasicsSubCommunityLabel,
              style: AppTypography.titleMedium.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            NmTextField(
              label: l10n.registrationSubCasteLabel,
              hint: l10n.profileBasicsSubCommunityHint,
              controller: _subCommunityCtrl,
              textCapitalization: TextCapitalization.words,
              onChanged: (v) =>
                  setState(() => _form = _form.copyWith(subCommunity: v)),
            ),
          ],
        ),
      ],
    );
  }
}
