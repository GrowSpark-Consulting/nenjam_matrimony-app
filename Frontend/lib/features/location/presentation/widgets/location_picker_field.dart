import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/feedback/selection_list_skeleton.dart';
import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/location_models.dart';

/// One level of the country → state → city cascade (and, since
/// [ReligionOption] is the same shape, of the religion → community cascade
/// too — see `religion_models.dart`).
///
/// Reuses [AppSheets.show] for the sheet chrome rather than a bespoke modal,
/// so picking a city looks and behaves like every other bottom sheet in the
/// app. Labels are unique within a parent — a city's code is derived from its
/// own label, so two cities in one state cannot share one — which is what
/// makes it safe to round-trip through the sheet by label and map the chosen
/// one back to its [LocationOption].
///
/// The sheet opens on tap immediately, before the options are known to be
/// loaded — a member should never wait on a spinner before seeing so much as
/// a modal appear. What the sheet shows once open — a skeleton, an error with
/// retry, "nothing here", or the real list — tracks [optionsProvider] live via
/// its own [Consumer], so a response arriving while the sheet is already open
/// (the common case for a field this fast) replaces the skeleton in place
/// rather than requiring the member to close and reopen it. That live view
/// goes straight through Riverpod's own dependency graph rather than a
/// hand-rolled bridge, so it behaves exactly like every other `ref.watch` in
/// the app — including while the sheet's route sits on top of (not inside)
/// the widget this field lives on.
class LocationPickerField extends ConsumerWidget {
  const LocationPickerField({
    super.key,
    required this.label,
    required this.hint,
    required this.options,
    required this.optionsProvider,
    required this.value,
    required this.onChanged,
    this.legacyValue = '',
    this.enabled = true,
    this.disabledHint,
    this.onRetry,
    this.labelStyle,
    this.loadingMessage,
    this.emptyMessage,
    this.errorMessage,
  });

  final String label;

  /// Overrides the caption style. Onboarding renders its field captions as
  /// bold section headings (see `OnboardingLocationField`) while the wizard
  /// uses the quieter default, so one component serves both rather than the
  /// two flows growing separate pickers.
  final TextStyle? labelStyle;
  final String hint;

  /// Free text from before the master data existed, shown when there is no
  /// code-backed [value]. Displayed like a real value, not like a hint,
  /// because to the member it IS their answer.
  final String legacyValue;

  /// The options for this level, which may still be loading or failed. This
  /// is what the field itself renders (the suffix spinner/error icon, the
  /// "Could not load" text) — a snapshot taken by the caller's own
  /// `ref.watch`, same as before this field grew a sheet that opens early.
  final AsyncValue<List<LocationOption>> options;

  /// The live provider behind [options] — [statesProvider]`(code)`,
  /// [citiesProvider]`(code)`, `religionsProvider`, `communitiesProvider(code)`
  /// — watched directly by the open sheet via its own [Consumer]. Passing the
  /// provider itself (not just its current value) is what lets the sheet
  /// react to a response that lands after it opens.
  final ProviderListenable<AsyncValue<List<LocationOption>>> optionsProvider;

  final LocationOption? value;
  final ValueChanged<LocationOption?> onChanged;

  /// False while the parent level has no selection — there is nothing to
  /// list yet, and tapping should say so rather than open a sheet with
  /// nothing in it.
  final bool enabled;
  final String? disabledHint;

  /// Invoked when the member taps "Try again" after a load failure, either
  /// from the field itself or from inside the open sheet.
  final VoidCallback? onRetry;

  /// Shown inside the sheet, above a [SelectionListSkeleton], while the
  /// options are loading. Callers give this the specific noun ("Loading
  /// states...", "Finding cities in Gujarat...") so the member always knows
  /// what is being fetched rather than staring at a generic spinner.
  final String? loadingMessage;

  /// Shown inside the sheet when the options resolved with no items.
  final String? emptyMessage;

  /// Shown inside the sheet when the options failed, next to a retry action.
  final String? errorMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = options.hasError && !options.isLoading;
    final loading = options.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: labelStyle ?? AppTypography.labelMedium),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: !enabled ? null : () => _open(context),
          child: InputDecorator(
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        failed
                            ? Icons.error_outline_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: failed
                            ? AppColors.error
                            : AppColors.textSecondaryLight,
                        size: 22,
                      ),
              ),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            child: Text(
              _displayText,
              style: AppTypography.bodyMedium.copyWith(
                color: _hasValue ? null : AppColors.textSecondaryLight,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (failed && onRetry != null) ...[
          const SizedBox(height: 6),
          // A failure the member can act on. Without this the field is simply
          // stuck, and the only way forward is to restart the app.
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ],
    );
  }

  /// Whether the field is showing the member's own answer rather than a hint.
  bool get _hasValue => value != null || legacyValue.isNotEmpty;

  String get _displayText {
    if (value != null) return value!.label;
    if (legacyValue.isNotEmpty) return legacyValue;
    if (!enabled) return disabledHint ?? hint;
    if (options.hasError && !options.isLoading) return 'Could not load';
    return hint;
  }

  Future<void> _open(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final container = ProviderScope.containerOf(context);
    final selected = await AppSheets.show<String>(
      context,
      title: label,
      child: _AsyncOptionSheetBody(
        optionsProvider: optionsProvider,
        selectedLabel: value?.label,
        loadingMessage: loadingMessage ?? hint,
        emptyMessage: emptyMessage ?? l10n.commonNoMatches,
        errorMessage: errorMessage ?? 'Could not load',
        onRetry: onRetry,
      ),
    );
    if (selected == null) return;

    // firstWhere with a fallback rather than a bang: the sheet can only
    // return a label it was given, but a null here would be a crash in the
    // member's face, and doing nothing is the honest failure. Read (not
    // watch) straight off the container — this field has already been
    // popped off the widget tree's build phase by the time the sheet closes.
    final available = container.read(optionsProvider).valueOrNull ??
        const <LocationOption>[];
    for (final option in available) {
      if (option.label == selected) {
        onChanged(option);
        return;
      }
    }
  }
}

/// The sheet body for [LocationPickerField]. Watches [optionsProvider] live,
/// through its own [Consumer], so it can move from skeleton to error to the
/// real list without being closed and reopened — the field may still be
/// loading at the moment the member taps it, and a fast response should just
/// land in front of them.
class _AsyncOptionSheetBody extends StatefulWidget {
  const _AsyncOptionSheetBody({
    required this.optionsProvider,
    required this.selectedLabel,
    required this.loadingMessage,
    required this.emptyMessage,
    required this.errorMessage,
    required this.onRetry,
  });

  final ProviderListenable<AsyncValue<List<LocationOption>>> optionsProvider;
  final String? selectedLabel;
  final String loadingMessage;
  final String emptyMessage;
  final String errorMessage;
  final VoidCallback? onRetry;

  @override
  State<_AsyncOptionSheetBody> createState() => _AsyncOptionSheetBodyState();
}

class _AsyncOptionSheetBodyState extends State<_AsyncOptionSheetBody> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(widget.optionsProvider);

        if (state.isLoading) {
          return _SheetStatus(
            message: widget.loadingMessage,
            child: const Padding(
              padding: EdgeInsets.only(top: AppSpacing.md),
              child: SelectionListSkeleton(),
            ),
          );
        }

        if (state.hasError) {
          return _SheetStatus(
            message: widget.errorMessage,
            icon: Icons.error_outline_rounded,
            iconColor: AppColors.error,
            action: widget.onRetry == null
                ? null
                : TextButton.icon(
                    onPressed: widget.onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(AppLocalizations.of(context).commonRetry),
                  ),
          );
        }

        final all = state.valueOrNull ?? const <LocationOption>[];
        if (all.isEmpty) {
          return _SheetStatus(message: widget.emptyMessage);
        }

        final filtered = _query.isEmpty
            ? all
            : all
                .where((o) => o.label.toLowerCase().contains(_query))
                .toList(growable: false);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                controller: _searchController,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context).commonSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                style: AppTypography.bodyMedium,
              ),
            ),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(AppLocalizations.of(context).commonNoMatches),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final option = filtered[index];
                        final isSelected = option.label == widget.selectedLabel;
                        return ListTile(
                          title: Text(
                            option.label,
                            style: AppTypography.bodyMedium.copyWith(
                              fontWeight:
                                  isSelected ? FontWeight.w700 : FontWeight.w400,
                              color: isSelected ? AppColors.primary : null,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.primary,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, option.label),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// A one-line message, optionally with a leading icon and a trailing action —
/// the loading / error / empty presentation shared by every state in
/// [_AsyncOptionSheetBody] except the loaded list itself.
///
/// The message is always drawn as real text, never left implied by the
/// shimmer alone — a screen reader user gets "Loading states..." the same way
/// a sighted member gets the caption, and [Semantics.liveRegion] announces it
/// the moment the sheet opens rather than waiting to be focused.
class _SheetStatus extends StatelessWidget {
  const _SheetStatus({
    required this.message,
    this.child,
    this.icon,
    this.iconColor,
    this.action,
  });

  final String message;
  final Widget? child;
  final IconData? icon;
  final Color? iconColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: iconColor ?? AppColors.textSecondaryLight),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Text(
                    message,
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.textSecondaryLight),
                  ),
                ),
              ],
            ),
          ),
          if (child != null) child!,
          if (action != null) ...[
            const SizedBox(height: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}
