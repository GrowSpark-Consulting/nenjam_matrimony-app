import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';

import '../../../../core/animations/app_animations.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/tokens/app_touch_target.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/buttons/icon_button.dart';
import '../../../../core/widgets/inputs/app_dropdown.dart';
import '../../../../core/widgets/layout/responsive_layout.dart';
import '../../../../core/widgets/system_ui/nm_status_bar_style.dart';
import '../../../../l10n/app_localizations.dart';

/// The pieces every onboarding step shares — the crest above the headline,
/// the bold-heading-over-a-dropdown field, the pinned footer, and the two
/// small rules (content width, "which answers are still missing") that would
/// otherwise be copy-pasted onto each of the ten screens.
/// Below this usable height the full footer does not fit — see the compact
/// branch in [OnboardingStepScaffold].
const double _kCompactFooterHeight = 420;

abstract final class OnboardingScaffold {
  /// Keeps the column of content from stretching to full tablet width,
  /// where a bled-out field runs far wider than it is tall.
  static const double contentMaxWidth = 480;

  /// The value to open a field on: whatever the draft holds, but only if it
  /// is still one of the offered options. A value the list no longer
  /// carries (a custom one typed in Edit Profile, say) opens blank rather
  /// than silently selecting something the member did not choose.
  static String restore(String value, List<String> options) =>
      options.contains(value) ? value : '';

  /// The options a dropdown needs in order to be able to *display* [value].
  ///
  /// [restore] blanks a stored answer that is not one of [options], because
  /// `DropdownButtonFormField` asserts when its `value` is absent from its
  /// items. That is the right trade for a closed vocabulary, but the wrong
  /// one for location: the state and city lists are a hand-curated subset,
  /// and real profiles hold answers outside it — `Punjab`, `Goa`,
  /// `Bengaluru`, `chennai` — none of which the list offers. Blanking them
  /// meant a returning member opened the step with an empty required field,
  /// and saving replaced a real stored value with whatever they picked
  /// instead. Silent data loss, on a screen that was only meant to re-open.
  ///
  /// Appending the stored value keeps the widget's invariant satisfied while
  /// the answer survives, so the member sees what they actually entered and
  /// can keep it or change it deliberately.
  ///
  /// Deliberately append-only and non-destructive: no trimming of the stored
  /// value into a different one, no case folding onto a similar entry, no
  /// alias matching. Reconciling `Bengaluru` with `Bangalore` needs an
  /// authoritative source, and guessing it here is exactly the silent
  /// rewrite this exists to prevent.
  static List<String> optionsWith(List<String> options, String value) {
    if (value.isEmpty || options.contains(value)) return options;
    return [...options, value];
  }

  /// "Select your Religion to continue." / "…your Religion and Community…".
  ///
  /// [names] is the already-localized, screen-ordered list of unanswered
  /// required fields, so the sentence reads down the screen. Null when
  /// nothing is missing — which is exactly when Continue becomes tappable.
  /// Whether the viewport is too short for the full chrome — a landscape
  /// phone with the keyboard raised. The header and footer both shrink, and
  /// the validation line and any legal text are dropped, so every control
  /// stays reachable instead of overflowing.
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).height -
          MediaQuery.viewInsetsOf(context).bottom <
      _kCompactFooterHeight;

  static String? validationHint(AppLocalizations l10n, List<String> names) {
    if (names.isEmpty) return null;
    final joined = names.length == 1
        ? names.single
        : l10n.profileBasicsFieldJoin(
            names.take(names.length - 1).join(', '),
            names.last,
          );
    return l10n.profileBasicsMissing(joined);
  }
}

/// A whole onboarding step: crest, optional eyebrow, headline, the step's
/// fields, and a pinned CTA that stays disabled — with a line saying why —
/// until the step is complete.
///
/// Every step in the flow is this same shape, so the back/save/advance
/// wiring lives here once. A step supplies its fields and its rule; it does
/// not re-implement scrolling, safe areas, the disabled-CTA explanation, or
/// what to do when a save fails.
class OnboardingStepScaffold extends StatefulWidget {
  final String headline;

  /// Small line above the headline ("Great! Few more details").
  final String? eyebrow;

  final IconData crestIcon;
  final List<Widget> fields;

  /// Where Back goes when there is nothing to pop — every step is reached
  /// with `go`, so that is the normal case.
  final String backRoute;

  /// Where a successful save advances to.
  final String nextRoute;

  final bool isComplete;

  /// Localized names of the still-unanswered required fields.
  final List<String> validationNames;

  /// Persists the step. Throwing keeps the member on the screen: the
  /// onboarding gate reads the backend's copy, so advancing after a failed
  /// save would only bounce them back on the next launch.
  final Future<void> Function() onSave;

  /// Overrides the CTA label ("Create Profile" on the income step).
  final String? ctaLabel;

  /// Rendered between the fields and the footer — the photo step's actions,
  /// the about step's helper line.
  final Widget? trailing;

  const OnboardingStepScaffold({
    super.key,
    required this.headline,
    required this.crestIcon,
    required this.fields,
    required this.backRoute,
    required this.nextRoute,
    required this.isComplete,
    required this.validationNames,
    required this.onSave,
    this.eyebrow,
    this.ctaLabel,
    this.trailing,
  });

  @override
  State<OnboardingStepScaffold> createState() => _OnboardingStepScaffoldState();
}

class _OnboardingStepScaffoldState extends State<OnboardingStepScaffold> {
  bool _saving = false;

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(widget.backRoute);
    }
  }

  Future<void> _continue() async {
    if (!widget.isComplete || _saving) return;
    setState(() => _saving = true);
    // The server's own words when it has any, so a step the client thought
    // was valid but the API refused says *why*. Every catch used to collapse
    // to "please try again", which is the right thing for a dropped
    // connection and useless for a rejected answer: a member whose date of
    // birth the API declined — an older build, a value typed either side of
    // the UTC day boundary — was told nothing they could act on and had no
    // way out of the step.
    var failed = false;
    String? reason;
    try {
      await widget.onSave();
    } on ApiException catch (e) {
      failed = true;
      // 4xx only. A 5xx or a transport failure carries a message written for
      // an operator, not a member, so those keep the generic line.
      reason = (e.statusCode ?? 500) < 500 ? e.message : null;
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (failed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(reason ?? AppLocalizations.of(context).commonTryAgain),
          ),
        );
      return;
    }
    context.go(widget.nextRoute);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final compact = OnboardingScaffold.isCompact(context);

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
                OnboardingBackRow(onBack: _back, compact: compact),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    child: NmContentConstraint(
                      maxWidth: OnboardingScaffold.contentMaxWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.eyebrow != null) ...[
                            Center(
                              child: Text(
                                widget.eyebrow!,
                                textAlign: TextAlign.center,
                                style: AppTypography.bodyMedium
                                    .copyWith(color: colors.onSurfaceVariant),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.base),
                          ],
                          Center(child: OnboardingCrest(icon: widget.crestIcon)),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            widget.headline,
                            style: AppTypography.headlineSmall.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.base),
                          for (final field in widget.fields) ...[
                            field,
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          if (widget.trailing != null) widget.trailing!,
                        ],
                      ),
                    ),
                  ),
                ),
                // Compact once the usable body height cannot fit the full
                // footer — a landscape phone with the keyboard raised leaves
                // barely 130dp, against ~136dp for the back row plus a
                // full-size CTA and its hint. The same trade the wizard's
                // sticky bar makes: the hint goes, the button shrinks to
                // 48dp, and every control stays reachable.
                OnboardingFooter(
                  compact: compact,
                  validationHint: compact
                      ? null
                      : OnboardingScaffold.validationHint(
                          l10n,
                          widget.validationNames,
                        ),
                  child: NmGradientButton(
                    label: widget.ctaLabel ?? l10n.commonContinue,
                    icon: Icons.arrow_forward_rounded,
                    isLoading: _saving,
                    height: compact ? AppTouchTarget.minSize : 56,
                    onPressed: widget.isComplete ? _continue : null,
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

/// The back control every onboarding step wears, shrunk when the viewport
/// cannot spare a full 48dp row.
class OnboardingBackRow extends StatelessWidget {
  final VoidCallback onBack;
  final bool compact;

  const OnboardingBackRow({
    super.key,
    required this.onBack,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final button = NmIconButton(
      icon: Icons.arrow_back_rounded,
      tooltip: AppLocalizations.of(context).registrationBack,
      onPressed: onBack,
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: compact
            ? SizedBox(height: AppSpacing.xl2, child: button)
            : button,
      ),
    );
  }
}

/// The soft circular crest each onboarding step wears above its headline.
/// Token-drawn rather than an asset, so it re-tints with the colour scheme
/// instead of needing a second, dark-mode artwork file.
class OnboardingCrest extends StatelessWidget {
  final IconData icon;

  const OnboardingCrest({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppAnimations.scale(
      Container(
        width: AppSpacing.xl4,
        height: AppSpacing.xl4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.primaryContainer,
        ),
        child: Icon(icon, size: AppSpacing.xl, color: colors.primary),
      ),
    );
  }
}

/// A bold section heading over a dropdown — the reference's vertical rhythm,
/// built on the design system's [NmDropdown] rather than a second dropdown
/// implementation.
///
/// [showHeading] is false for the first field of a screen whose headline
/// already names it ("Your religion" over the Religion field), so the word
/// is not printed twice.
class OnboardingDropdownField extends StatelessWidget {
  /// The field's own caption, inside the input.
  final String label;

  /// The bold section heading above it. Defaults to [label] — they differ
  /// where the reference shows a short heading over a longer caption
  /// ("Height" over "Your height").
  final String? heading;

  final String hint;
  final String value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final bool showHeading;

  /// Appends the asterisk the reference screens use to mark a required
  /// field. Purely presentational — the rule itself lives on the form model.
  final bool isRequired;

  /// Renders an info affordance beside the field when set — for a label
  /// whose meaning is not self-evident (Community, income).
  final String? helpText;

  const OnboardingDropdownField({
    super.key,
    required this.label,
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
    this.heading,
    this.showHeading = true,
    this.isRequired = false,
    this.helpText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final field = NmDropdown<String>(
      label: isRequired ? '$label *' : label,
      hint: hint,
      // The empty sentinel the form starts on is not one of the items, so
      // it has to become null or DropdownButtonFormField asserts.
      value: value.isEmpty ? null : value,
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: Text(option)),
      ],
      onChanged: onChanged,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading) ...[
          Text(
            heading ?? label,
            style: AppTypography.titleMedium.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (helpText == null)
          field
        else
          Row(
            children: [
              Expanded(child: field),
              const SizedBox(width: AppSpacing.md),
              OnboardingHelpIcon(text: helpText!),
            ],
          ),
      ],
    );
  }
}

/// Tap-to-explain affordance — the "?" the reference screens put beside a
/// label whose meaning is not obvious.
class OnboardingHelpIcon extends StatelessWidget {
  final String text;

  const OnboardingHelpIcon({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: text,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 8),
      child: Icon(
        Icons.help_outline_rounded,
        size: AppSpacing.xl,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The pinned bottom of an onboarding step: the CTA, with an optional line
/// above it saying *why* the CTA is disabled rather than greying it out with
/// no explanation — the same contract RegistrationStickyBottomBar holds to
/// in the wizard.
class OnboardingFooter extends StatelessWidget {
  final Widget child;
  final String? validationHint;

  /// Trims the footer's own padding for a viewport that cannot fit it —
  /// see the caller in [OnboardingStepScaffold].
  final bool compact;

  /// Rendered under the CTA when set — the contact step's terms line.
  final String? legalText;

  const OnboardingFooter({
    super.key,
    required this.child,
    this.validationHint,
    this.legalText,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        compact ? AppSpacing.sm : AppSpacing.base,
      ),
      child: NmContentConstraint(
        maxWidth: OnboardingScaffold.contentMaxWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (validationHint != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: AppSpacing.base,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      validationHint!,
                      style: AppTypography.labelSmall
                          .copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            AppAnimations.buttonPress(child),
            if (legalText != null && !compact) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                legalText!,
                textAlign: TextAlign.center,
                style: AppTypography.labelSmall
                    .copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
