import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/animations/app_animations.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/tokens/app_animation_tokens.dart';
import '../../../../core/theme/tokens/app_radius.dart';
import '../../../../core/theme/tokens/app_touch_target.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/buttons/icon_button.dart';
import '../../../../core/widgets/layout/responsive_layout.dart';
import '../../../../core/widgets/system_ui/nm_status_bar_style.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/onboarding_forms.dart';
import '../../domain/models/profile_for_relation.dart';
import '../providers/registration_provider.dart';

/// The options wrap into two columns on a phone, so each pill is capped at
/// half the content width (minus the gap between them) — a long label
/// therefore wraps onto the next row instead of stretching across it.
const double _kPillColumns = 2;

/// Gap between pills, both across a row and between rows. Shared with the
/// half-width maths above so the two can never drift apart and leave the
/// second column clipped.
const double _kPillGap = AppSpacing.sm;

/// Keeps the column of content from stretching to full tablet width, where
/// a bled-out pill grid would leave the two columns far apart.
const double _kContentMaxWidth = 480;

/// "This Profile is for" — the first step of profile creation, and the only
/// writer of `BasicDetails.profileCreatedFor`.
///
/// Every path that finishes sign-up lands here (see `PostAuthDestination`),
/// including a resumed registration whose draft already carries an answer —
/// which is why the initial selection is restored from the draft rather than
/// defaulted. Nothing is selected until the user (or that draft) picks one,
/// and Continue stays disabled until then: an unanswered question has to
/// stay distinguishable from a real answer all the way to the backend.
class CreateProfileForPage extends ConsumerStatefulWidget {
  const CreateProfileForPage({super.key});

  @override
  ConsumerState<CreateProfileForPage> createState() =>
      _CreateProfileForPageState();
}

class _CreateProfileForPageState extends ConsumerState<CreateProfileForPage> {
  ProfileForRelation? _selected;

  /// The draft's own representation, not a second gender state: this mirrors
  /// `BasicDetails.gender` while the screen is open and is written straight
  /// back to it on Continue. Empty until the member picks.
  String _gender = '';

  @override
  void initState() {
    super.initState();
    // Start on the answer the draft already carries rather than a hard
    // default, so stepping back here from the wizard — or resuming a
    // registration on a new device — shows the choice the user made
    // instead of silently reverting it.
    final basic = ref.read(registrationProvider).basicDetails;
    _selected = ProfileForRelation.fromStorage(basic.profileCreatedFor);
    // Gender is read from the one field that has always held it. Stepping
    // back here from Your Name — or resuming after PostAuthDestination
    // rehydrates the draft — reopens on the answer already given.
    _gender = basic.gender;
  }

  /// Localized display label for a stored gender value. The value itself
  /// stays English ('Male' / 'Female'), exactly as the Edit Profile wizard's
  /// Basic Info step stores it — `BasicDetails.toJson` is what maps it to the
  /// API's MALE / FEMALE, so nothing here may pre-convert.
  String _genderLabel(AppLocalizations l10n, String value) => switch (value) {
        'Male' => l10n.genderMale,
        'Female' => l10n.genderFemale,
        _ => value,
      };

  /// Localized label for a relation. [ProfileForRelation.storageValue] is
  /// never localized — only what the user reads is.
  String _label(AppLocalizations l10n, ProfileForRelation relation) =>
      switch (relation) {
        ProfileForRelation.myself => l10n.profileForOptionMyself,
        ProfileForRelation.son => l10n.profileForOptionSon,
        ProfileForRelation.daughter => l10n.profileForOptionDaughter,
        ProfileForRelation.brother => l10n.profileForOptionBrother,
        ProfileForRelation.sister => l10n.profileForOptionSister,
        ProfileForRelation.friend => l10n.profileForOptionFriend,
        ProfileForRelation.relative => l10n.profileForOptionRelative,
      };

  /// Leaves the first onboarding step. Reached via `go` from every sign-up
  /// path (which replaces the whole stack), so there is usually nothing to
  /// pop back to — the landing page is what precedes sign-up, and is where
  /// Back belongs now that the welcome interstitial is out of the flow.
  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.registrationLanding);
    }
  }

  /// Both answers are required, so Continue stays inert until both are
  /// given — the same rule [ProfileForForm.isComplete] states and the same
  /// one PostAuthDestination gates this step on.
  bool get _isComplete => _selected != null && _gender.isNotEmpty;

  void _continue() {
    final selected = _selected;
    if (selected == null || !_isComplete) return;
    // CREATE mode, but WITHOUT resetting the draft.
    //
    // This used to call startCreateMode(), which blanks the whole draft. That
    // was harmless while this was the only way in, and destructive the moment
    // Back existed: a member who reached Your Name, tapped Back to change
    // "profile for", and continued again lost every answer they had given —
    // name, date of birth, religion, the lot. The reset belongs where a
    // genuinely new signup starts, and it is already there: the landing
    // page's sign-up buttons call startCreateMode() before routing here (see
    // RegistrationLandingPage._signUpWith), and the Google path arrives via
    // PostAuthDestination, which restores the account's own draft in CREATE
    // mode. Setting only the mode here keeps the stale-EDIT-session guard
    // this call was really for.
    final notifier = ref.read(registrationProvider.notifier);
    notifier.enterCreateMode();
    notifier.applyProfileFor(
      ProfileForForm(
        profileCreatedFor: selected.storageValue,
        gender: _gender,
      ),
    );
    context.go(RouteNames.onboardingNameDob);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return NmPageStatusBar(
      background: theme.scaffoldBackgroundColor,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: NmIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: l10n.registrationBack,
                      onPressed: _back,
                    ),
                  ),
                ),
                // Scrolls rather than compresses: seven pills, a notice and
                // a 200% text scale together outgrow a short phone.
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    child: NmContentConstraint(
                      maxWidth: _kContentMaxWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Center(child: _ProfileForIllustration()),
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            l10n.registrationProfileForTitle,
                            style: AppTypography.headlineLarge.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _ProfileForOptions(
                            options: ProfileForRelation.values,
                            selected: _selected,
                            labelOf: (relation) => _label(l10n, relation),
                            onSelected: (relation) =>
                                setState(() => _selected = relation),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _GenderChoice(
                            label: l10n.registrationGenderLabel,
                            selected: _gender,
                            labelOf: (g) => _genderLabel(l10n, g),
                            onSelected: (g) => setState(() => _gender = g),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _ProfileForNotice(text: l10n.profileForNotice),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.base,
                  ),
                  child: NmContentConstraint(
                    maxWidth: _kContentMaxWidth,
                    child: AppAnimations.buttonPress(
                      NmGradientButton(
                        label: l10n.commonContinue,
                        icon: Icons.arrow_forward_rounded,
                        // Null until both answers are given —
                        // NmGradientButton renders its own disabled state
                        // from that.
                        onPressed: _isComplete ? _continue : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The gender control, in the exact form the app already uses for it — the
/// `ChoiceChip` row from the Edit Profile wizard's Basic Info step, down to
/// the `AppColors.primarySurface` selected fill. Deliberately not restyled
/// into a `_ProfileForPill`: gender is a two-option question the member has
/// met elsewhere in the app, and it should look the same everywhere.
class _GenderChoice extends StatelessWidget {
  final String label;

  /// The stored value ('Male' / 'Female'), or empty when unanswered.
  final String selected;

  final String Function(String) labelOf;
  final ValueChanged<String> onSelected;

  const _GenderChoice({
    required this.label,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        Row(
          // Values stay English (stored and emitted); only the label is
          // localized.
          children: ['Male', 'Female'].map((g) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: ChoiceChip(
                  label: Center(child: Text(labelOf(g))),
                  selected: selected == g,
                  selectedColor: AppColors.primarySurface,
                  onSelected: (_) => onSelected(g),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Soft plum medallion standing in for the photo the user has not added
/// yet. Drawn from theme tokens rather than an asset so it re-tints with
/// the colour scheme instead of needing a second, dark-mode artwork file.
class _ProfileForIllustration extends StatelessWidget {
  const _ProfileForIllustration();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppAnimations.scale(
      Container(
        width: AppSpacing.xl7,
        height: AppSpacing.xl7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.primaryContainer,
        ),
        child: Icon(
          Icons.person_rounded,
          size: AppSpacing.xl3,
          color: colors.primary,
        ),
      ),
    );
  }
}

/// The single-choice pill group.
///
/// A [Wrap] rather than a grid: pills size to their own label, so a locale
/// with longer words reflows to fewer per row instead of ellipsizing, while
/// the cap on each pill keeps the two-column reading at every phone width.
class _ProfileForOptions extends StatelessWidget {
  final List<ProfileForRelation> options;
  final ProfileForRelation? selected;
  final String Function(ProfileForRelation) labelOf;
  final ValueChanged<ProfileForRelation> onSelected;

  const _ProfileForOptions({
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pillMaxWidth =
            (constraints.maxWidth - _kPillGap) / _kPillColumns;
        return Wrap(
          spacing: _kPillGap,
          runSpacing: AppSpacing.md,
          children: [
            for (final option in options)
              _ProfileForPill(
                label: labelOf(option),
                isSelected: option == selected,
                maxWidth: pillMaxWidth,
                onTap: () => onSelected(option),
              ),
          ],
        );
      },
    );
  }
}

class _ProfileForPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final double maxWidth;
  final VoidCallback onTap;

  const _ProfileForPill({
    required this.label,
    required this.isSelected,
    required this.maxWidth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // Selected and unselected differ in fill, border weight and label weight
    // — not in the radio dot alone. The state has to be readable at a glance
    // across a seven-option grid.
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: isSelected,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          minHeight: AppTouchTarget.minSize,
        ),
        child: Material(
          color: isSelected ? colors.primaryContainer : colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.pill,
            side: BorderSide(
              color: isSelected ? colors.primary : colors.outline,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Padding(
              // Trim, because the pill's width budget is half a phone: the
              // chrome (padding + radio + gap) is what a label has to fit
              // around, and at 360dp a wider one pushes "My Daughter" onto
              // a second line.
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RadioIndicator(isSelected: isSelected),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      label,
                      style: AppTypography.labelLarge.copyWith(
                        color: isSelected
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ring-and-dot radio, matching the single-choice semantics of the group.
class _RadioIndicator extends StatelessWidget {
  final bool isSelected;

  const _RadioIndicator({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppAnimationTokens.fast,
      curve: AppAnimationTokens.luxuryCurve,
      width: AppSpacing.lg,
      height: AppSpacing.lg,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.surface,
        border: Border.all(
          color: isSelected ? colors.primary : colors.outline,
          width: 2,
        ),
      ),
      child: Center(
        child: AnimatedContainer(
          duration: AppAnimationTokens.fast,
          curve: AppAnimationTokens.luxuryCurve,
          width: isSelected ? AppSpacing.sm : 0,
          height: isSelected ? AppSpacing.sm : 0,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.primary,
          ),
        ),
      ),
    );
  }
}

/// Nenjam's own trust notice — about what this platform is for and what the
/// moderation team actually removes, rather than generic legal boilerplate.
class _ProfileForNotice extends StatelessWidget {
  final String text;

  const _ProfileForNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppAnimations.fade(
      Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: AppRadius.br16,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: AppSpacing.lg,
              color: colors.secondary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                text,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
      delay: const Duration(milliseconds: 150),
    );
  }
}
