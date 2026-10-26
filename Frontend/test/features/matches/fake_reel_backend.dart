import 'package:nenjam_matrimony/features/discover/domain/entities/discover_feed_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_profile_page.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/repositories/discover_repository.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';

/// Test-only reel feed: profiles with the longest realistic name and a full
/// set of detail chips, so overflow and overlap show up if they exist.
class FakeReelBackend implements DiscoverRepository {
  FakeReelBackend({this.count = 3});

  final int count;

  @override
  Future<DiscoverProfilePage> getDiscoverProfilesPage({
    int page = 1,
    int limit = 20,
    String? cursor,
  }) async => DiscoverProfilePage(
    items: [
      for (var i = 1; i <= count; i++)
        DiscoveryProfileEntity(
          id: 'p$i',
          matrimonyId: 'NM-P$i',
          name: 'Venkatalakshmi Subramaniam Krishnaswamy',
          age: 28,
          location: 'Thiruvananthapuram, Kerala',
          profession: 'Senior Software Development Engineer',
          education: 'M.Tech Computer Science',
          photoUrls: const [],
          religion: 'Hindu',
          community: 'Tamil Brahmin',
          height: "5'4\"",
          diet: 'Vegetarian',
          maritalStatus: 'Never Married',
          motherTongue: 'Tamil',
          isVerified: true,
        ),
    ],
    page: 1,
    hasMore: false,
  );

  @override
  Future<DiscoverFeedEntity> getDiscoverFeed() async =>
      const DiscoverFeedEntity(
        aiRecommended: [],
        recentlyJoined: [],
        stories: [],
        verifiedProfiles: [],
        nearYou: [],
        premiumMembers: [],
        profileCompletionPercent: 0,
      );
}

/// Overrides the reel's data source with [FakeReelBackend].
final fakeReelOverride = discoverRepositoryProvider.overrideWithValue(
  FakeReelBackend(),
);
