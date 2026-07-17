import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/chips/app_chips.dart';
import '../../../../core/widgets/chips/info_chip.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/search_providers.dart';

/// Shown in place of results while the search field is empty and no
/// filters are active: locally-saved recent searches (tap to search again,
/// swipe/tap-x to remove one, or clear all) plus a static set of popular
/// search terms.
class SearchSuggestions extends ConsumerWidget {
  final ValueChanged<String> onSelect;

  const SearchSuggestions({super.key, required this.onSelect});

  static const _popularSearches = [
    'Engineer',
    'Doctor',
    'NRI',
    'MBA',
    'Government Job',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final recent = ref.watch(recentSearchesProvider);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.base),
      children: [
        if (recent.isNotEmpty) ...[
          _SectionHeader(
            title: l10n.searchRecentTitle,
            trailing: TextButton(
              onPressed: () => ref.read(recentSearchesProvider.notifier).clearAll(),
              child: Text(l10n.searchClearAll),
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final term in recent)
                GestureDetector(
                  onTap: () => onSelect(term),
                  child: NmRemovableChip(
                    label: term,
                    onDeleted: () => ref.read(recentSearchesProvider.notifier).removeOne(term),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        _SectionHeader(title: l10n.searchPopularTitle),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final term in _popularSearches)
              NmInfoChip(label: term, onTap: () => onSelect(term)),
          ],
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: AppTypography.titleSmall.copyWith(
            color: AppColors.textPrimaryLight,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
