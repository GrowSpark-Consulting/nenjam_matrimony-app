import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/profile_options.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/tokens/app_radius.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/onboarding_forms.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 2 — "Your religion": religion, community, and the country the member
/// lives in. All three required.
///
/// The country is asked here rather than on the State & City step because it
/// decides whether "state" and "city" are even the right questions to ask
/// later; the two location steps together fill `LocationDetails`.
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
    // an answer the member already gave. Only values still offered are
    // restored, so a custom religion typed in Edit Profile does not select a
    // stale dropdown entry.
    final draft = ref.read(registrationProvider);
    _form = OnboardingReligionForm(
      religion: OnboardingScaffold.restore(
        draft.religionDetails.religion,
        ProfileOptions.religions,
      ),
      community: OnboardingScaffold.restore(
        draft.religionDetails.community,
        ProfileOptions.communitiesFor(draft.religionDetails.religion),
      ),
      livingIn: OnboardingScaffold.restore(
        draft.locationDetails.country,
        ProfileOptions.countries,
      ),
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

  /// Changing religion re-scopes the community list. The current answer is
  /// cleared only when the new list no longer offers it — a member who
  /// corrects "Hindu" to "Jain" keeps a community both share, and nothing
  /// else on the form is touched.
  void _onReligionChanged(String religion) {
    setState(() {
      final stillValid = ProfileOptions.communitiesFor(religion)
          .contains(_form.community);
      _form = _form.copyWith(
        religion: religion,
        community: stillValid ? _form.community : '',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final communities = ProfileOptions.communitiesFor(_form.religion);

    return OnboardingStepScaffold(
      headline: l10n.onboardingReligionHeadline,
      crestIcon: Icons.groups_rounded,
      backRoute: RouteNames.createProfileFor,
      nextRoute: RouteNames.onboardingContact,
      isComplete: _form.isComplete,
      validationNames:
          _form.missingFields.map((f) => _label(l10n, f)).toList(),
      onSave: () => ref
          .read(registrationProvider.notifier)
          .applyOnboardingReligion(_form),
      fields: [
        OnboardingDropdownField(
          label: l10n.onboardingReligionLabel,
          hint: l10n.onboardingReligionHint,
          value: _form.religion,
          options: ProfileOptions.religions,
          showHeading: false,
          isRequired: true,
          onChanged: (v) => _onReligionChanged(v ?? ''),
        ),
        OnboardingDropdownField(
          label: l10n.onboardingCommunityLabel,
          hint: l10n.onboardingCommunityHint,
          value: _form.community,
          options: communities,
          isRequired: true,
          helpText: l10n.onboardingCommunityHelp,
          onChanged: (v) =>
              setState(() => _form = _form.copyWith(community: v ?? '')),
        ),
        OnboardingDropdownField(
          label: l10n.onboardingLivingInLabel,
          hint: l10n.onboardingLivingInHint,
          value: _form.livingIn,
          options: ProfileOptions.countries,
          isRequired: true,
          onChanged: (v) =>
              setState(() => _form = _form.copyWith(livingIn: v ?? '')),
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
