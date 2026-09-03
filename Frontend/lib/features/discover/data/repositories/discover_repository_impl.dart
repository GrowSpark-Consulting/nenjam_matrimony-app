import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../domain/entities/discover_feed_entity.dart';
import '../../domain/entities/discover_profile_page.dart';
import '../../domain/repositories/discover_repository.dart';
import '../models/discovery_profile_model.dart';
import '../models/story_model.dart';

/// Backend-backed Discover feed. Fetches the single preference-filtered feed
/// from `GET /discover` (see backend `matches` module) and distributes the
/// real profiles across the screen's sections.
///
/// The Discover screen renders several sections (New Today, AI Recommended,
/// Recently Joined, Verified, Premium) — a presentation concept the
/// backend doesn't model as separate lists yet. So the one flat feed is
/// *partitioned*, round-robin, into those buckets: every profile lands in
/// exactly one section. That fills each section with real people and — because
/// every card shares a `Hero(tag: 'profile-photo-$id')` — guarantees no
/// profile id is ever shown twice on the same screen, which Flutter would
/// otherwise reject with a duplicate-hero error on navigation. As the pool of
/// finalized profiles grows, the sections fill out evenly with no code change.
class DiscoverRepositoryImpl implements DiscoverRepository {
  DiscoverRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  /// Pull a generous single page — the feed is sectioned client-side, not
  /// infinite-scrolled, so one request covers the whole screen.
  static const _feedLimit = 50;

  /// Sections the feed is partitioned into, in priority order: the scarce
  /// first profiles fill the most prominent sections first.
  ///
  /// Five, not six, since "Near You" stopped being one of them: that section
  /// now renders real device-location results from `/profiles/nearby` (see
  /// `_NearYouSection`) instead of an arbitrary slice of this feed. Had the
  /// count stayed at six, the sixth bucket would still be filled here and then
  /// rendered nowhere — quietly dropping a sixth of every page off the screen.
  static const _sectionCount = 5;

  @override
  Future<DiscoverFeedEntity> getDiscoverFeed() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.discover,
      queryParameters: const {'page': 1, 'limit': _feedLimit},
    );
    final data =
        unwrapOrThrow(response.statusCode, response.data) ?? const {};

    final profiles = _parseProfiles(data);

    // Round-robin into disjoint buckets so ids never repeat across sections.
    final buckets = List.generate(
      _sectionCount,
      (_) => <DiscoveryProfileModel>[],
    );
    for (var i = 0; i < profiles.length; i++) {
      buckets[i % _sectionCount].add(profiles[i]);
    }

    return DiscoverFeedEntity(
      aiRecommended: buckets[0],
      recentlyJoined: buckets[1],
      verifiedProfiles: buckets[2],
      premiumMembers: buckets[3],
      stories: buckets[4].map(_toStory).toList(),
      // Always empty, and deliberately so: "near you" is a claim about
      // physical distance, and this endpoint knows nothing about where anyone
      // is. Real proximity comes from `/profiles/nearby` via
      // `nearbyNotifierProvider`, which needs the device's location and the
      // user's permission — neither of which exists here. Filling this with
      // arbitrary feed profiles is exactly the thing that made the old Near
      // You section a lie.
      //
      // The field stays on the entity because several screens still fold it
      // into a lookup pool of "every profile the feed returned"; contributing
      // nothing to those pools is correct, since the same profiles are now
      // distributed across the four buckets above.
      nearYou: const [],
      // Not surfaced by the feed screen — the drawer/Profile read the real
      // backend completion via its own provider. Kept 0 rather than invented.
      profileCompletionPercent: 0,
      fallbackUsed: data['fallbackUsed'] == true,
      fallbackReason: (data['reason'] as String?) ?? '',
    );
  }

  @override
  Future<DiscoverProfilePage> getDiscoverProfilesPage({
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.discover,
      queryParameters: {'page': page, 'limit': limit},
    );
    final data =
        unwrapOrThrow(response.statusCode, response.data) ?? const {};
    return DiscoverProfilePage(
      items: _parseProfiles(data),
      page: (data['page'] as num?)?.toInt() ?? page,
      hasMore: data['hasMore'] == true,
    );
  }

  /// Parses the `items` of a `/discover` response into deduped, gender-
  /// normalized profiles. Shared by the sectioned feed and the paginated feed.
  List<DiscoveryProfileModel> _parseProfiles(Map<String, dynamic> data) {
    // Normalize gender casing (backend emits lowercase; the gender-aware photo
    // placeholder keys off 'Male'/'Female') and dedupe by id.
    final seen = <String>{};
    final profiles = <DiscoveryProfileModel>[];
    for (final raw in (data['items'] as List<dynamic>? ?? const [])) {
      final json = Map<String, dynamic>.from(raw as Map);
      json['gender'] = normalizeProfileGender(json['gender']);
      final profile = DiscoveryProfileModel.fromJson(json);
      if (seen.add(profile.id)) profiles.add(profile);
    }
    return profiles;
  }

  /// A "New Today" bubble wraps a real profile so tapping it opens Profile
  /// Detail exactly like any card. First name only, to fit the 76px bubble.
  StoryModel _toStory(DiscoveryProfileModel p) => StoryModel(
        id: p.id,
        name: p.name.isEmpty ? p.name : p.name.split(' ').first,
        imageUrl: p.photoUrls.isNotEmpty ? p.photoUrls.first : '',
        hasNewStory: true,
        gender: p.gender,
        profile: p,
      );
}
