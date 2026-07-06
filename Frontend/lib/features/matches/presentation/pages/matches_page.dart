import 'package:flutter/material.dart';

import '../../../../core/widgets/cards/match_card.dart';
import '../../../../l10n/app_localizations.dart';

/// Matches tab displaying AI curated matches, shortlists, and mutual likes.
class MatchesPage extends StatelessWidget {
  const MatchesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.matchesTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.matchesTabNew('24')),
              Tab(text: l10n.matchesTabShortlisted),
              Tab(text: l10n.matchesTabMutual),
            ],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              // New Matches List
              ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: 6,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  return NmMatchCard(
                    name: index % 2 == 0 ? 'Sruthi M.' : 'Lakshmi V.',
                    age: '25 yrs',
                    matchPercentage: 96 - (index * 3),
                    matchReason: 'Horoscope & Profession match',
                  );
                },
              ),

              // Shortlisted Tab
              Center(child: Text(l10n.matchesShortlistedEmpty)),

              // Mutual Likes Tab
              Center(child: Text(l10n.matchesMutualEmpty)),
            ],
          ),
        ),
      ),
    );
  }
}
