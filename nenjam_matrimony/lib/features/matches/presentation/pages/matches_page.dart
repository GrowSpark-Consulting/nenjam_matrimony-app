import 'package:flutter/material.dart';

import '../../../../core/widgets/cards/match_card.dart';

/// Matches tab displaying AI curated matches, shortlists, and mutual likes.
class MatchesPage extends StatelessWidget {
  const MatchesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Matches'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'New (24)'),
              Tab(text: 'Shortlisted'),
              Tab(text: 'Mutual'),
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
              const Center(child: Text('Shortlisted Profiles')),

              // Mutual Likes Tab
              const Center(child: Text('Mutual Likes')),
            ],
          ),
        ),
      ),
    );
  }
}
