import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/profile_navigation.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/secondary_button.dart';
import '../../../../core/widgets/feedback/empty_state.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../core/widgets/feedback/shimmer_widget.dart';
import '../../../../core/widgets/inputs/search_bar.dart';
import '../../../../core/widgets/sheets/app_sheets.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../../discover/presentation/providers/discover_providers.dart';
import '../../domain/entities/search_filters_entity.dart';
import '../providers/search_providers.dart';
import '../widgets/search_filter_sheet.dart';
import '../widgets/search_result_card.dart';
import '../widgets/search_suggestions.dart';

/// Premium matrimony search: real-time query against the shared discover
/// feed, an advanced filter bottom sheet, recent/popular search
/// suggestions, and the existing [NmProfileCard] grid for results.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryProvider));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  void _submit(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    ref.read(searchQueryProvider.notifier).state = trimmed;
    if (trimmed.isNotEmpty) {
      ref.read(recentSearchesProvider.notifier).add(trimmed);
    }
  }

  void _selectSuggestion(String term) {
    _controller.text = term;
    _controller.selection = TextSelection.collapsed(offset: term.length);
    _submit(term);
  }

  Future<void> _openFilters() async {
    final l10n = AppLocalizations.of(context);
    await AppSheets.show<void>(
      context,
      title: l10n.searchFilterSheetTitle,
      child: const SearchFilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = ref.watch(searchQueryProvider);
    final filters = ref.watch(searchFiltersProvider);
    final resultsAsync = ref.watch(searchResultsProvider);
    final showSuggestions = query.isEmpty && filters.isEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.searchTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: NmSearchBar(
                controller: _controller,
                hint: l10n.searchHint,
                onChanged: _onChanged,
                onSubmitted: _submit,
                onFilterTap: _openFilters,
              ),
            ),
            if (!showSuggestions)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    resultsAsync.maybeWhen(
                      data: (results) => Text(
                        l10n.searchShowingMatches('${results.length}'),
                        style: AppTypography.titleSmall,
                      ),
                      orElse: () => const SizedBox.shrink(),
                    ),
                    if (filters.activeCount > 0)
                      TextButton(
                        onPressed: () =>
                            ref.read(searchFiltersProvider.notifier).state =
                                const SearchFilters.empty(),
                        child: Text(
                          '${l10n.searchFilterReset} (${filters.activeCount})',
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: showSuggestions
                  ? SearchSuggestions(onSelect: _selectSuggestion)
                  : resultsAsync.when(
                      data: (results) {
                        if (results.isEmpty) {
                          return Center(
                            child: NmEmptyState(
                              title: l10n.searchEmptyResultsTitle,
                              message: l10n.searchEmptyResultsSubtitle,
                              icon: Icons.search_off_rounded,
                              action: NmSecondaryButton(
                                label: l10n.searchResetFiltersButton,
                                onPressed: () =>
                                    ref
                                            .read(
                                              searchFiltersProvider.notifier,
                                            )
                                            .state =
                                        const SearchFilters.empty(),
                                width: 220,
                                height: 48,
                              ),
                            ),
                          );
                        }
                        return _SearchResultsGrid(profiles: results);
                      },
                      loading: () => const _SearchResultsShimmerGrid(),
                      error: (_, __) => Center(
                        child: NmErrorWidget(
                          onRetry: () => ref.invalidate(discoverFeedProvider),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

int _crossAxisCountFor(double width) {
  if (width >= AppConstants.desktopBreakpoint) return 4;
  if (width >= AppConstants.tabletBreakpoint) return 3;
  return 2;
}

class _SearchResultsGrid extends StatelessWidget {
  final List<DiscoveryProfileEntity> profiles;

  const _SearchResultsGrid({required this.profiles});

  void _notify(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final crossAxisCount = _crossAxisCountFor(MediaQuery.sizeOf(context).width);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        0,
        AppSpacing.base,
        AppSpacing.base,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: AppSpacing.base,
        crossAxisSpacing: AppSpacing.base,
        childAspectRatio: 0.68,
      ),
      itemCount: profiles.length,
      itemBuilder: (context, index) {
        final profile = profiles[index];
        return SearchResultCard(
          profile: profile,
          onTap: () => openProfileDetail(context, profile),
          onInterested: () =>
              _notify(context, '${l10n.actionInterested}: ${profile.name}'),
          onShortlist: () =>
              _notify(context, '${l10n.profileCardShortlist}: ${profile.name}'),
        );
      },
    );
  }
}

class _SearchResultsShimmerGrid extends StatelessWidget {
  const _SearchResultsShimmerGrid();

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = _crossAxisCountFor(MediaQuery.sizeOf(context).width);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        0,
        AppSpacing.base,
        AppSpacing.base,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: AppSpacing.base,
        crossAxisSpacing: AppSpacing.base,
        childAspectRatio: 0.68,
      ),
      itemCount: crossAxisCount * 3,
      itemBuilder: (_, __) => const NmShimmerProfileCard(),
    );
  }
}
