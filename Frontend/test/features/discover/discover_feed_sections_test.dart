import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/discover/data/models/discovery_profile_model.dart';
import 'package:nenjam_matrimony/features/discover/data/repositories/discover_repository_impl.dart';

/// Discover's "Verified Profiles", "Premium Members", "Recently Joined" and
/// "New Today" sections used to be filled by list position alone, so any
/// member could be shown under a verified badge, as premium, or as new. Each
/// must only ever hold members the backend reports as qualifying.
void main() {
  DiscoveryProfileModel p(
    String id, {
    bool verified = false,
    bool premium = false,
    DateTime? joinedAt,
  }) => DiscoveryProfileModel.fromJson({
    'id': id,
    'name': 'Member $id',
    'age': 30,
    'location': 'Chennai',
    'profession': 'Engineer',
    'photoUrls': <String>[],
    'isVerified': verified,
    'isPremium': premium,
    if (joinedAt != null) 'joinedAt': joinedAt.toUtc().toIso8601String(),
  });

  final now = DateTime.utc(2026, 10, 26, 12);
  const recentlyJoinedBucket = 1;
  const newTodayBucket = 4;

  const verifiedBucket = 2;
  const premiumBucket = 3;

  List<String> ids(List<DiscoveryProfileModel> b) =>
      b.map((e) => e.id).toList();

  test('no unverified or non-premium member lands in those sections', () {
    final profiles = [
      for (var i = 0; i < 23; i++) p('$i', verified: i == 7, premium: i == 13),
    ];
    final buckets = DiscoverRepositoryImpl.partitionFeedSections(profiles);

    expect(buckets[verifiedBucket].every((m) => m.isVerified), isTrue);
    expect(buckets[premiumBucket].every((m) => m.isPremium), isTrue);
    expect(ids(buckets[verifiedBucket]), ['7']);
    expect(ids(buckets[premiumBucket]), ['13']);
  });

  test('every profile is placed exactly once', () {
    final profiles = [for (var i = 0; i < 17; i++) p('$i', verified: i.isEven)];
    final placed = DiscoverRepositoryImpl.partitionFeedSections(
      profiles,
    ).expand((b) => b).map((m) => m.id).toList();
    expect(placed, hasLength(17));
    expect(placed.toSet(), hasLength(17));
  });

  test('with nobody verified or premium, those sections stay empty', () {
    final buckets = DiscoverRepositoryImpl.partitionFeedSections([
      for (var i = 0; i < 10; i++) p('$i'),
    ]);
    expect(buckets[verifiedBucket], isEmpty);
    expect(buckets[premiumBucket], isEmpty);
  });

  test('when everyone qualifies it is the plain round-robin', () {
    final profiles = [
      for (var i = 0; i < 10; i++)
        p('$i', verified: true, premium: true, joinedAt: now),
    ];
    final buckets = DiscoverRepositoryImpl.partitionFeedSections(
      profiles,
      now: now,
    );
    for (var b = 0; b < 5; b++) {
      expect(ids(buckets[b]), ['$b', '${b + 5}']);
    }
  });

  test('only members who joined in the window are shown as new', () {
    final profiles = [
      p('today', joinedAt: now.subtract(const Duration(hours: 3))),
      p('lastWeek', joinedAt: now.subtract(const Duration(days: 6))),
      p('lastYear', joinedAt: now.subtract(const Duration(days: 400))),
      p('unknown'),
      p('future', joinedAt: now.add(const Duration(days: 1))),
    ];
    final buckets = DiscoverRepositoryImpl.partitionFeedSections([
      for (var r = 0; r < 4; r++) ...profiles,
    ], now: now);
    final newToday = buckets[newTodayBucket];
    final recent = buckets[recentlyJoinedBucket];

    expect(newToday.every((m) => m.id == 'today'), isTrue);
    expect(recent.every((m) => m.id == 'today' || m.id == 'lastWeek'), isTrue);
    for (final id in ['lastYear', 'unknown', 'future']) {
      expect(newToday.any((m) => m.id == id), isFalse, reason: id);
      expect(recent.any((m) => m.id == id), isFalse, reason: id);
    }
  });

  test('with no join dates, both "new" sections stay empty', () {
    final buckets = DiscoverRepositoryImpl.partitionFeedSections([
      for (var i = 0; i < 12; i++) p('$i'),
    ], now: now);
    expect(buckets[recentlyJoinedBucket], isEmpty);
    expect(buckets[newTodayBucket], isEmpty);
  });

  test('joinedAt round-trips through the wire model', () {
    final joined = DateTime.utc(2026, 10, 25, 9, 30);
    final m = p('x', joinedAt: joined);
    expect(m.joinedAt, joined);
    expect(DiscoveryProfileModel.fromJson(m.toJson()).joinedAt, joined);
    expect(p('y').joinedAt, isNull);
  });
}
