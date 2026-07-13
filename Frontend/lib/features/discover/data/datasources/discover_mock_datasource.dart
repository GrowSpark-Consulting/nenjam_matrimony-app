import '../../../../core/constants/asset_paths.dart';
import '../../domain/entities/compatibility_entity.dart';
import '../models/discovery_profile_model.dart';
import '../models/story_model.dart';

/// In-memory stand-in for a future `GET /api/discover-feed` call. Every
/// method returns the same shape a Dio-backed datasource would — callers
/// never know the difference. Photos intentionally point at the bundled
/// [AssetPaths.imgPlaceholder] rather than any external/network URL until
/// real profile photography is wired up.
class DiscoverMockDataSource {
  Future<List<StoryModel>> fetchStories() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const [
      StoryModel(id: 's1', name: 'Priya', imageUrl: AssetPaths.imgPlaceholder, hasNewStory: true),
      StoryModel(id: 's2', name: 'Rahul', imageUrl: AssetPaths.imgPlaceholder),
      StoryModel(id: 's3', name: 'Ananya', imageUrl: AssetPaths.imgPlaceholder, hasNewStory: true),
      StoryModel(id: 's4', name: 'Vikram', imageUrl: AssetPaths.imgPlaceholder),
      StoryModel(id: 's5', name: 'Meera', imageUrl: AssetPaths.imgPlaceholder, hasNewStory: true),
    ];
  }

  Future<List<DiscoveryProfileModel>> fetchAiRecommended() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return const [
      DiscoveryProfileModel(
        id: 'ai1',
        matrimonyId: 'NM100234',
        name: 'Advika',
        age: 27,
        location: 'London',
        profession: 'Senior Product Designer',
        education: 'Masters in Design',
        photoUrls: [AssetPaths.imgPlaceholder],
        isVerified: true,
        isPremium: true,
        isPsychologyCompleted: true,
        horoscopeAvailable: true,
        photoProtected: false,
        phoneVerified: true,
        compatibility: CompatibilityEntity(
          aiMatchPercent: 98,
          astroMatchPercent: 92,
          psychologyMatchPercent: 90,
          overallCompatibility: 95,
          lifestyleMatchPercent: 88,
          familyMatchPercent: 93,
          educationMatchPercent: 96,
          valuesMatchPercent: 91,
          goalsMatchPercent: 89,
        ),
        tags: ['NRI', 'Verified Identity', 'Premium Plus'],
        religion: 'Hindu',
        caste: 'Iyer',
        community: 'Tamil Brahmin',
        height: '5\'5"',
        diet: 'Vegetarian',
      ),
      DiscoveryProfileModel(
        id: 'ai2',
        matrimonyId: 'NM100587',
        name: 'Kavya',
        age: 26,
        location: 'Singapore',
        profession: 'Investment Analyst',
        education: 'MBA Finance',
        photoUrls: [AssetPaths.imgPlaceholder],
        isVerified: true,
        isPremium: false,
        isPsychologyCompleted: true,
        horoscopeAvailable: true,
        photoProtected: true,
        phoneVerified: false,
        compatibility: CompatibilityEntity(
          aiMatchPercent: 91,
          astroMatchPercent: 84,
          psychologyMatchPercent: 88,
          overallCompatibility: 89,
          lifestyleMatchPercent: 82,
          familyMatchPercent: 86,
          educationMatchPercent: 90,
          valuesMatchPercent: 85,
          goalsMatchPercent: 83,
        ),
        tags: ['NRI', 'Verified Identity'],
        religion: 'Hindu',
        caste: 'Mudaliar',
        community: 'Tamil',
        height: '5\'4"',
        diet: 'Eggetarian',
      ),
    ];
  }

  Future<List<DiscoveryProfileModel>> fetchRecentlyJoined() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return const [
      DiscoveryProfileModel(
        id: 'rj1',
        matrimonyId: 'NM100812',
        name: 'Vikram',
        age: 28,
        location: 'Chennai',
        profession: 'Software Engineer',
        education: 'B.Tech CSE',
        photoUrls: [AssetPaths.imgPlaceholder],
        isVerified: true,
        phoneVerified: true,
        compatibility: CompatibilityEntity(aiMatchPercent: 85),
      ),
      DiscoveryProfileModel(
        id: 'rj2',
        matrimonyId: 'NM100933',
        name: 'Rahul',
        age: 30,
        location: 'Bangalore',
        profession: 'Business Owner',
        education: 'B.Com',
        photoUrls: [AssetPaths.imgPlaceholder],
        isPremium: true,
        compatibility: CompatibilityEntity(aiMatchPercent: 91),
      ),
    ];
  }

  Future<List<DiscoveryProfileModel>> fetchVerifiedProfiles() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    return const [
      DiscoveryProfileModel(
        id: 'vp1',
        matrimonyId: 'NM100056',
        name: 'Ishaan',
        age: 30,
        location: 'New York',
        profession: 'Fintech Founder',
        education: 'MS Computer Science',
        photoUrls: [AssetPaths.imgPlaceholder],
        isVerified: true,
        isPremium: true,
        isPsychologyCompleted: true,
        horoscopeAvailable: true,
        phoneVerified: true,
        compatibility: CompatibilityEntity(
          aiMatchPercent: 94,
          astroMatchPercent: 88,
          psychologyMatchPercent: 82,
          overallCompatibility: 98,
        ),
        tags: ['NRI', 'Verified Identity', 'Premium Plus'],
        religion: 'Hindu',
        caste: 'Gupta',
        community: 'Punjabi',
        height: '5\'11"',
        diet: 'Non-Vegetarian',
      ),
    ];
  }

  Future<List<DiscoveryProfileModel>> fetchNearYou() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const [
      DiscoveryProfileModel(
        id: 'ny1',
        matrimonyId: 'NM101045',
        name: 'Meera',
        age: 26,
        location: 'Chennai',
        profession: 'MBA',
        education: 'MBA',
        photoUrls: [AssetPaths.imgPlaceholder],
        distanceKm: 2.4,
      ),
      DiscoveryProfileModel(
        id: 'ny2',
        matrimonyId: 'NM101099',
        name: 'Ananya',
        age: 25,
        location: 'Chennai',
        profession: 'Doctor',
        education: 'MBBS',
        photoUrls: [AssetPaths.imgPlaceholder],
        isVerified: true,
        distanceKm: 4.8,
      ),
    ];
  }

  Future<List<DiscoveryProfileModel>> fetchPremiumMembers() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const [
      DiscoveryProfileModel(
        id: 'pm1',
        matrimonyId: 'NM100003',
        name: 'Alex Vance',
        age: 32,
        location: 'New York',
        profession: 'Elite Member',
        education: '',
        photoUrls: [AssetPaths.imgPlaceholder],
        isPremium: true,
        isVerified: true,
        phoneVerified: true,
      ),
    ];
  }

  Future<int> fetchProfileCompletionPercent() async => 65;
}
