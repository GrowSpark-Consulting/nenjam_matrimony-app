import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/profile_card.dart';
import '../../../../core/widgets/chips/info_chip.dart';
import '../../../../core/widgets/inputs/search_bar.dart';
import '../../../../l10n/app_localizations.dart';

/// Search and Discovery screen with filter chips and profile grid.
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.searchTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: NmSearchBar(onFilterTap: () {}),
            ),

            // Quick Filter Chips
            SizedBox(
              height: 40,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                children: [
                  NmInfoChip(label: l10n.searchFilterVerifiedOnly, isSelected: true),
                  const SizedBox(width: 8),
                  NmInfoChip(label: l10n.searchFilterNearMe),
                  const SizedBox(width: 8),
                  NmInfoChip(label: l10n.searchFilterDoctor),
                  const SizedBox(width: 8),
                  NmInfoChip(label: l10n.searchFilterEngineer),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Results Count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(l10n.searchShowingMatches('1,240'),
                      style: AppTypography.titleSmall),
                  TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.sort_rounded, size: 18),
                    label: Text(l10n.searchSortButton),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.68,
                ),
                itemCount: 8,
                itemBuilder: (context, index) {
                  return NmProfileCard(
                    name: 'Karthik Raja',
                    age: '29 yrs',
                    location: 'Coimbatore',
                    profession: 'Architect',
                    isVerified: index % 2 == 0,
                    isPremium: index % 3 == 0,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
