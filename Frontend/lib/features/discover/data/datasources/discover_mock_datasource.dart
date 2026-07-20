import '../../domain/entities/compatibility_entity.dart';
import '../models/discovery_profile_model.dart';
import '../models/story_model.dart';

/// In-memory stand-in for a future `GET /api/discover-feed` call. Every
/// method returns the same shape a Dio-backed datasource would — callers
/// never know the difference. `photoUrls`/`imageUrl` are deliberately left
/// empty (no real photography exists yet) rather than pointed at a stand-in
/// asset — a non-empty URL would short-circuit every card/story widget's
/// "no photo" branch and skip `NmGenderPlaceholder` entirely, rendering
/// whatever that stand-in image actually is instead of the intended
/// gender-aware fallback.
class DiscoverMockDataSource {
  Future<List<StoryModel>> fetchStories() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // "New Today" bubbles represent newly-joined members, not ephemeral
    // stories — each carries a full [DiscoveryProfileModel] so tapping
    // one opens Profile Detail exactly like any other profile card.
    return const [
      StoryModel(
        id: 'nt1',
        name: 'Priya',
        imageUrl: '',
        hasNewStory: true,
        gender: 'Female',
        profile: DiscoveryProfileModel(
          id: 'nt1',
          matrimonyId: 'NM101201',
          name: 'Priya',
          gender: 'Female',
          age: 26,
          location: 'Mumbai',
          profession: 'UX Designer',
          education: 'B.Des',
          photoUrls: [],
          compatibility: CompatibilityEntity(aiMatchPercent: 87),
          religion: 'Hindu',
          diet: 'Vegetarian',
        ),
      ),
      StoryModel(
        id: 'nt2',
        name: 'Rahul',
        imageUrl: '',
        gender: 'Male',
        profile: DiscoveryProfileModel(
          id: 'nt2',
          matrimonyId: 'NM101202',
          name: 'Rahul',
          gender: 'Male',
          age: 29,
          location: 'Pune',
          profession: 'Product Manager',
          education: 'MBA',
          photoUrls: [],
          compatibility: CompatibilityEntity(aiMatchPercent: 82),
          religion: 'Hindu',
          diet: 'Non-Vegetarian',
        ),
      ),
      StoryModel(
        id: 'nt3',
        name: 'Ananya',
        imageUrl: '',
        hasNewStory: true,
        gender: 'Female',
        profile: DiscoveryProfileModel(
          id: 'nt3',
          matrimonyId: 'NM101203',
          name: 'Ananya',
          gender: 'Female',
          age: 27,
          location: 'Hyderabad',
          profession: 'Data Scientist',
          education: 'M.Tech',
          photoUrls: [],
          isVerified: true,
          compatibility: CompatibilityEntity(aiMatchPercent: 90),
          religion: 'Hindu',
          diet: 'Vegetarian',
        ),
      ),
      StoryModel(
        id: 'nt4',
        name: 'Vikram',
        imageUrl: '',
        gender: 'Male',
        profile: DiscoveryProfileModel(
          id: 'nt4',
          matrimonyId: 'NM101204',
          name: 'Vikram',
          gender: 'Male',
          age: 31,
          location: 'Delhi',
          profession: 'Civil Engineer',
          education: 'B.E',
          photoUrls: [],
          compatibility: CompatibilityEntity(aiMatchPercent: 78),
          religion: 'Hindu',
          diet: 'Non-Vegetarian',
        ),
      ),
      StoryModel(
        id: 'nt5',
        name: 'Meera',
        imageUrl: '',
        hasNewStory: true,
        gender: 'Female',
        profile: DiscoveryProfileModel(
          id: 'nt5',
          matrimonyId: 'NM101205',
          name: 'Meera',
          gender: 'Female',
          age: 25,
          location: 'Chennai',
          profession: 'Architect',
          education: 'B.Arch',
          photoUrls: [],
          isVerified: true,
          compatibility: CompatibilityEntity(aiMatchPercent: 85),
          religion: 'Hindu',
          diet: 'Vegetarian',
        ),
      ),
    ];
  }

  Future<List<DiscoveryProfileModel>> fetchAiRecommended() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return const [
      DiscoveryProfileModel(
        id: 'ai1',
        matrimonyId: 'NM100234',
        name: 'Advika',
        gender: 'Female',
        age: 27,
        location: 'London',
        profession: 'Senior Product Designer',
        education: 'Masters in Design',
        photoUrls: [],
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
        gender: 'Female',
        age: 26,
        location: 'Singapore',
        profession: 'Investment Analyst',
        education: 'MBA Finance',
        photoUrls: [],
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
        gender: 'Male',
        age: 28,
        location: 'Chennai',
        profession: 'Software Engineer',
        education: 'B.Tech CSE',
        photoUrls: [],
        isVerified: true,
        phoneVerified: true,
        compatibility: CompatibilityEntity(aiMatchPercent: 85),
      ),
      DiscoveryProfileModel(
        id: 'rj2',
        matrimonyId: 'NM100933',
        name: 'Rahul',
        gender: 'Male',
        age: 30,
        location: 'Bangalore',
        profession: 'Business Owner',
        education: 'B.Com',
        photoUrls: [],
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
        gender: 'Male',
        age: 30,
        location: 'New York',
        profession: 'Fintech Founder',
        education: 'MS Computer Science',
        photoUrls: [],
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
        gender: 'Female',
        age: 26,
        location: 'Chennai',
        profession: 'MBA',
        education: 'MBA',
        photoUrls: [],
        distanceKm: 2.4,
      ),
      DiscoveryProfileModel(
        id: 'ny2',
        matrimonyId: 'NM101099',
        name: 'Ananya',
        gender: 'Female',
        age: 25,
        location: 'Chennai',
        profession: 'Doctor',
        education: 'MBBS',
        photoUrls: [],
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
        gender: 'Male',
        age: 32,
        location: 'New York',
        profession: 'Elite Member',
        education: '',
        photoUrls: [],
        isPremium: true,
        isVerified: true,
        phoneVerified: true,
      ),
    ];
  }

  Future<int> fetchProfileCompletionPercent() async => 65;
}
