import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/cards/ai_recommendation_card.dart';
import '../../../../core/widgets/cards/premium_banner.dart';
import '../../../../core/widgets/cards/profile_card.dart';
import '../../../../core/widgets/cards/profile_completion_card.dart';

/// Main Home Page with AI recommendations, profile completion, and discovery grid.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nenjam Matrimony'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile completion CTA
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: NmProfileCompletionCard(
                  percentage: 65,
                  nextStep: 'Upload Horoscope',
                ),
              ),
              const SizedBox(height: 24),

              // Premium Banner
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: NmPremiumBanner(),
              ),
              const SizedBox(height: 32),

              // AI Recommendations Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'AI Match Recommendations',
                        style: AppTypography.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text('See All'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 260,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  itemCount: 5,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    return NmAiRecommendationCard(
                      name: 'Ananya S.',
                      compatibility: 94 - (index * 2),
                      reason: 'Shared values & lifestyle',
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),

              // Recently Joined Profiles
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Recently Joined', style: AppTypography.titleLarge),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.68,
                ),
                itemCount: 4,
                itemBuilder: (context, index) {
                  return NmProfileCard(
                    name: index % 2 == 0 ? 'Priya Raman' : 'Divya K.',
                    age: '26 yrs',
                    location: 'Chennai',
                    profession: 'Software Engineer',
                    isVerified: index == 0,
                    isPremium: index == 1,
                    isOnline: index % 2 == 0,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
