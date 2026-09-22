import 'package:flutter/material.dart';

import '../../../../core/constants/profile_options.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/app_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import 'onboarding_scaffold.dart';
import 'other_option_field.dart';
import 'registration_helper_tip.dart';
import 'step_body.dart';

/// Step 2 — Religion Details
class StepReligion extends StatefulWidget {
  final ReligionDetails details;
  final void Function(ReligionDetails) onChanged;
  /// See [StepBody.scrollable].
  final bool scrollable;

  const StepReligion({
    super.key,
    required this.details,
    required this.onChanged,
    this.scrollable = true,
  });

  @override
  State<StepReligion> createState() => _StepReligionState();
}

class _StepReligionState extends State<StepReligion> {
  late String _religion;
  late final TextEditingController _casteCtrl;
  late final TextEditingController _gothraCtrl;
  late final TextEditingController _denominationCtrl;
  late String _community;
  late String _subCommunity;

  /// The structured pair captured by the onboarding Religion step, which
  /// picks from the live religion master data. This step's own options come
  /// from [ProfileOptions], which carries labels only — so these are carried
  /// through an edit rather than re-derived, and cleared only when the
  /// religion changes (see [_onReligionChanged]).
  late String _religionCode;
  late String _communityCode;

  static const _religions = [...ProfileOptions.religions, 'Other'];

  @override
  void initState() {
    super.initState();
    _religion = widget.details.religion;
    _casteCtrl = TextEditingController(text: widget.details.caste);
    _gothraCtrl = TextEditingController(text: widget.details.gothra);
    _denominationCtrl = TextEditingController(text: widget.details.denomination);
    _community = widget.details.community;
    _subCommunity = widget.details.subCaste;
    _religionCode = widget.details.religionCode;
    _communityCode = widget.details.communityCode;
  }

  @override
  void dispose() {
    _casteCtrl.dispose();
    _gothraCtrl.dispose();
    _denominationCtrl.dispose();
    super.dispose();
  }

  /// Options for the chosen religion, plus this step's own "Other" escape and
  /// — crucially — whatever is already stored.
  ///
  /// `optionsWith` is what stops an edit from silently discarding data: a
  /// member whose community predates this list (or was typed through "Other")
  /// still sees their own answer selected instead of an empty field that
  /// overwrites it on save.
  List<String> get _communityOptions => OnboardingScaffold.optionsWith(
        [...ProfileOptions.communitiesFor(_religion), 'Other'],
        _community,
      );

  List<String> get _subCommunityOptions => OnboardingScaffold.optionsWith(
        [...ProfileOptions.subCommunities, 'Other'],
        _subCommunity,
      );

  /// Changing religion clears a community the new religion does not offer,
  /// and the sub-community with it. A community that IS still valid is kept —
  /// re-picking a religion should not cost an answer that remains true.
  void _onReligionChanged(String religion) {
    setState(() {
      final changed = religion != _religion;
      _religion = religion;
      // A code identifies the religion it was captured for, so a real change
      // invalidates it — and this step has no master-data lookup to mint a
      // replacement. Dropping it falls back to the free-text religion above,
      // which is exactly what a draft written before the master data existed
      // looks like (see ReligionDetails.religionCode).
      if (changed) _religionCode = '';
      if (!ProfileOptions.isCommunityInReligion(religion, _community)) {
        _community = '';
        _subCommunity = '';
        _communityCode = '';
      } else if (changed) {
        // The community label still stands under the new religion, but its
        // code was scoped to the old one.
        _communityCode = '';
      }
    });
    _emit();
  }

  /// Rebuilds [ReligionDetails] from this step's fields.
  ///
  /// Built with `copyWith` on the incoming details rather than a fresh
  /// [ReligionDetails], so `religionCode`/`communityCode` survive an edit.
  /// This step offers [ProfileOptions] — plain labels, no codes — while the
  /// onboarding Religion step picks from the live religion master data and
  /// stores both halves. Constructing a new instance here dropped both codes
  /// to `''`, and `ReligionDetails.toJson` then omitted them, so editing any
  /// field on this step silently discarded the structured pair onboarding had
  /// captured.
  ///
  /// [_onReligionChanged] clears them deliberately when the religion changes;
  /// everywhere else they are carried through untouched. No code is invented
  /// here — this step has no source for one.
  void _emit() {
    widget.onChanged(widget.details.copyWith(
      religion: _religion,
      caste: _casteCtrl.text.trim(),
      subCaste: _subCommunity,
      gothra: _gothraCtrl.text.trim(),
      denomination: _denominationCtrl.text.trim(),
      community: _community,
      religionCode: _religionCode,
      communityCode: _communityCode,
    ));
  }

  /// Localized display label for a stored religion value (value stays English).
  String _religionLabel(AppLocalizations l10n, String value) => switch (value) {
        'Hindu' => l10n.religionHindu,
        'Christian' => l10n.religionChristian,
        'Muslim' => l10n.religionMuslim,
        'Jain' => l10n.religionJain,
        'Sikh' => l10n.religionSikh,
        'Buddhist' => l10n.religionBuddhist,
        'Inter-Religion' => l10n.religionInterReligion,
        'Other' => l10n.religionOther,
        _ => value,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StepBody(
      scrollable: widget.scrollable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.registrationWizardReligionHeadline, style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l10n.registrationWizardReligionHook, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondaryLight)),
          const SizedBox(height: 16),
          RegistrationHelperTip(text: l10n.registrationTipReligion),
          const SizedBox(height: 24),
          OtherOptionField(
            title: l10n.registrationReligionLabel,
            options: _religions,
            value: _religion,
            labelOf: (v) => _religionLabel(l10n, v),
            customFieldLabel: l10n.registrationSpecifyReligionLabel,
            customFieldHint: l10n.registrationSpecifyReligionHint,
            onChanged: _onReligionChanged,
          ),
          const SizedBox(height: 20),
          // Filtered by the religion above. Keyed on it so the dropdown
          // rebuilds its options when the religion changes rather than holding
          // a value the new list cannot show.
          OtherOptionField(
            key: ValueKey('community-$_religion'),
            title: l10n.registrationCommunityLabel,
            options: _communityOptions,
            value: _community,
            customFieldLabel: l10n.registrationSpecifyCommunityLabel,
            customFieldHint: l10n.registrationCommunityHint,
            // Picking a different community here invalidates the code the
            // onboarding step captured for the old one; this step offers
            // labels only, so there is no replacement code to store.
            onChanged: (v) {
              setState(() {
                if (v != _community) _communityCode = '';
                _community = v;
              });
              _emit();
            },
          ),
          const SizedBox(height: 16),
          // Optional. Never gates anything and never counts against
          // completeness — see required-fields.ts.
          OtherOptionField(
            key: ValueKey('subcommunity-$_religion'),
            title: l10n.registrationSubCasteLabel,
            options: _subCommunityOptions,
            value: _subCommunity,
            customFieldLabel: l10n.registrationSpecifySubCommunityLabel,
            customFieldHint: l10n.registrationSubCasteHint,
            onChanged: (v) { setState(() => _subCommunity = v); _emit(); },
          ),
          const SizedBox(height: 20),
          NmTextField(label: l10n.registrationCasteLabel, hint: l10n.registrationCasteHint, controller: _casteCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationGothraLabel, hint: l10n.registrationGothraHint, controller: _gothraCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          NmTextField(label: l10n.registrationDenominationLabel, hint: l10n.registrationDenominationHint, controller: _denominationCtrl, onChanged: (_) => _emit()),
          const SizedBox(height: 16),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
