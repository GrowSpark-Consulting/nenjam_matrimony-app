import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_feed_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_profile_page.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discovery_profile_entity.dart';
import 'package:nenjam_matrimony/features/discover/domain/repositories/discover_repository.dart';
import 'package:nenjam_matrimony/features/discover/presentation/pages/discover_page.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/inbox/domain/entities/conversation_entity.dart';
import 'package:nenjam_matrimony/features/inbox/domain/repositories/conversation_repository.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/pages/inbox_page.dart';
import 'package:nenjam_matrimony/features/inbox/presentation/providers/inbox_providers.dart';
import 'package:nenjam_matrimony/features/interests/domain/repositories/interests_repository.dart';
import 'package:nenjam_matrimony/features/interests/presentation/pages/interests_received_page.dart';
import 'package:nenjam_matrimony/features/interests/presentation/pages/interests_sent_page.dart';
import 'package:nenjam_matrimony/features/interests/presentation/providers/interests_provider.dart';
import 'package:nenjam_matrimony/features/matches/presentation/pages/matches_page.dart';
import 'package:nenjam_matrimony/features/notifications/domain/entities/notification_entity.dart';
import 'package:nenjam_matrimony/features/notifications/domain/repositories/notification_repository.dart';
import 'package:nenjam_matrimony/features/notifications/presentation/pages/notifications_page.dart';
import 'package:nenjam_matrimony/features/notifications/presentation/providers/notification_providers.dart';
import 'package:nenjam_matrimony/features/profile/presentation/pages/profile_page.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'package:nenjam_matrimony/features/profile_detail/presentation/pages/profile_detail_page.dart';
import 'package:nenjam_matrimony/features/profile_photos/data/repositories/photo_repository.dart';
import 'package:nenjam_matrimony/features/profile_photos/domain/models/user_photo.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/providers/photo_providers.dart';
import 'package:nenjam_matrimony/features/profile_views/domain/entities/profile_viewer_entity.dart';
import 'package:nenjam_matrimony/features/profile_views/domain/repositories/profile_views_repository.dart';
import 'package:nenjam_matrimony/features/profile_views/presentation/pages/profile_viewers_page.dart';
import 'package:nenjam_matrimony/features/profile_views/presentation/providers/profile_views_provider.dart';
import 'package:nenjam_matrimony/features/shortlist/domain/repositories/shortlist_repository.dart';
import 'package:nenjam_matrimony/features/shortlist/presentation/pages/shortlisted_page.dart';
import 'package:nenjam_matrimony/features/shortlist/presentation/providers/shortlist_provider.dart';

import 'features/matches/fake_reel_backend.dart';
import 'features/profile_detail/fake_profile_detail_repository.dart';
import 'support/responsive_harness.dart';

/// Every major data screen, POPULATED, at the responsive brief's eight
/// viewports. The older sweeps pump most of these with no data source, which
/// only ever audits a loading spinner; here each list is filled with
/// test-only records carrying the longest realistic values (Tamil full
/// names, long locations and professions) so overflow and clipping in the
/// real content surface. Fixtures exist only in this file.
const _briefSizes = [
  Size(320, 568),
  Size(375, 812),
  Size(430, 932),
  Size(600, 960),
  Size(768, 1024),
  Size(1024, 768),
  Size(1366, 768),
  Size(1920, 1080),
];

final _now = DateTime(2026, 10, 26, 12);

DiscoveryProfileEntity _member(int i) => DiscoveryProfileEntity(
  id: 'm$i',
  matrimonyId: 'NM-M$i',
  name: i.isEven
      ? 'Venkatalakshmi Subramaniam Krishnaswamy'
      : 'Arjun Ramachandran',
  age: 27 + i,
  location: 'Thiruvananthapuram, Kerala',
  profession: 'Senior Software Development Engineer',
  education: 'M.Tech Computer Science and Engineering',
  photoUrls: const [],
  religion: 'Hindu',
  community: 'Tamil Brahmin',
  height: "5'4\"",
  diet: 'Vegetarian',
  maritalStatus: 'Never Married',
  motherTongue: 'Tamil',
  isVerified: i.isEven,
  isPremium: i % 3 == 0,
  joinedAt: _now.subtract(Duration(hours: i * 5)),
);

final _members = [for (var i = 0; i < 12; i++) _member(i)];

class _Discover implements DiscoverRepository {
  @override
  Future<DiscoverFeedEntity> getDiscoverFeed() async => DiscoverFeedEntity(
    aiRecommended: _members.sublist(0, 3),
    recentlyJoined: _members.sublist(3, 6),
    stories: const [],
    verifiedProfiles: [_members[6]],
    nearYou: const [],
    premiumMembers: _members.sublist(9, 12),
    profileCompletionPercent: 0,
  );

  @override
  Future<DiscoverProfilePage> getDiscoverProfilesPage({
    int page = 1,
    int limit = 20,
    String? cursor,
  }) async => DiscoverProfilePage(items: _members, page: 1, hasMore: false);
}

class _Interests implements InterestsRepository {
  List<InterestRecord> _records(InterestStatus s) => [
    for (var i = 0; i < 6; i++)
      InterestRecord(
        id: 'i$i',
        profile: _members[i],
        sentAt: _now.subtract(Duration(days: i)),
        status: i.isEven ? s : InterestStatus.accepted,
      ),
  ];

  @override
  Future<List<InterestRecord>> getReceived({
    int page = 1,
    int limit = 20,
  }) async => _records(InterestStatus.pending);

  @override
  Future<List<InterestRecord>> getSent({int page = 1, int limit = 20}) async =>
      _records(InterestStatus.declined);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Shortlist implements ShortlistRepository {
  @override
  Future<List<DiscoveryProfileEntity>> getShortlisted({
    int page = 1,
    int limit = 20,
  }) async => _members;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications implements NotificationRepository {
  @override
  Future<NotificationResultPage> getNotifications({
    int page = 1,
    int limit = 20,
  }) async => NotificationResultPage(
    items: [
      for (var i = 0; i < 8; i++)
        NotificationEntity(
          id: 'n$i',
          type: NotificationType.values[i % NotificationType.values.length],
          title: '${_members[i].name} sent you an interest',
          message:
              '${_members[i].name} from ${_members[i].location} would like '
              'to connect with you. View their profile to respond.',
          createdAt: _now.subtract(Duration(hours: i * 7)),
          isRead: i > 2,
        ),
    ],
    page: 1,
    limit: 20,
    total: 8,
    hasMore: false,
  );

  @override
  Future<int> getUnreadCount() async => 3;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProfileViews implements ProfileViewsRepository {
  @override
  Future<List<ProfileViewerEntity>> getViewers({
    int page = 1,
    int limit = 20,
  }) async => [
    for (var i = 0; i < 6; i++)
      ProfileViewerEntity(
        profile: _members[i],
        viewedAt: _now.subtract(Duration(hours: i * 3)),
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Conversations implements ConversationRepository {
  @override
  Future<ConversationResultPage> getConversations({
    int page = 1,
    int limit = 20,
  }) async => ConversationResultPage(
    items: [
      for (var i = 0; i < 8; i++)
        ConversationEntity(
          id: 'c$i',
          profile: _members[i],
          lastMessage:
              'Thank you for accepting my interest — would you like to talk '
              'with our families this weekend in ${_members[i].location}?',
          lastMessageAt: _now.subtract(Duration(minutes: i * 40)),
          unreadCount: i.isEven ? 12 : 0,
          isPinned: i == 0,
        ),
    ],
    page: 1,
    limit: 20,
    total: 8,
    hasMore: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Photos implements PhotoRepository {
  @override
  Future<List<UserPhoto>> fetchPhotos() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A filled-in saved profile for My Profile, with long values.
final Map<String, dynamic> _draft = {
  'completionPercentage': 72,
  'data': {
    'basicDetails': {
      'firstName': 'Venkatalakshmi',
      'lastName': 'Subramaniam Krishnaswamy',
      'gender': 'FEMALE',
      'dob': '1996-03-21',
      'maritalStatus': 'NEVER_MARRIED',
    },
    'religionDetails': {'religion': 'Hindu', 'caste': 'Brahmin'},
    'locationDetails': {
      'country': 'India',
      'state': 'Kerala',
      'city': 'Thiruvananthapuram',
    },
    'educationDetails': {
      'qualification': 'M.Tech Computer Science and Engineering',
      'occupation': 'Senior Software Development Engineer',
    },
    'physicalDetails': {'height': "5'4\" (163 cm)"},
    'horoscopeDetails': {'rashi': 'Kumbha', 'nakshatra': 'Sathayam'},
  },
};

final _pages = <String, (Widget Function(), List<Override>)>{
  'DiscoverPage': (
    () => const DiscoverPage(),
    [discoverRepositoryProvider.overrideWithValue(_Discover())],
  ),
  'MatchesPage': (() => const MatchesPage(), [fakeReelOverride]),
  'ProfileDetailPage': (
    () => ProfileDetailPage(profile: _members[0]),
    [
      fakeProfileDetailOverride,
      discoverRepositoryProvider.overrideWithValue(_Discover()),
    ],
  ),
  'ProfilePage': (
    () => const ProfilePage(),
    [
      profileDraftResponseProvider.overrideWith((ref) async => _draft),
      photoRepositoryProvider.overrideWithValue(_Photos()),
      discoverRepositoryProvider.overrideWithValue(_Discover()),
    ],
  ),
  'InboxPage': (
    () => const InboxPage(),
    [conversationRepositoryProvider.overrideWithValue(_Conversations())],
  ),
  'InterestsReceivedPage': (
    () => const InterestsReceivedPage(),
    [interestsRepositoryProvider.overrideWithValue(_Interests())],
  ),
  'InterestsSentPage': (
    () => const InterestsSentPage(),
    [interestsRepositoryProvider.overrideWithValue(_Interests())],
  ),
  'ShortlistedPage': (
    () => const ShortlistedPage(),
    [shortlistRepositoryProvider.overrideWithValue(_Shortlist())],
  ),
  'NotificationsPage': (
    () => const NotificationsPage(),
    [notificationRepositoryProvider.overrideWithValue(_Notifications())],
  ),
  'ProfileViewersPage': (
    () => _routed(const ProfileViewersPage()),
    [profileViewsRepositoryProvider.overrideWithValue(_ProfileViews())],
  ),
};

/// Hosts [page] under a one-route [GoRouter], for screens that ask the router
/// whether they can pop (their back affordance depends on it).
Widget _routed(Widget page) => Router.withConfig(
  config: GoRouter(
    routes: [GoRoute(path: '/', builder: (_, __) => page)],
  ),
);

void main() {
  for (final MapEntry(key: name, value: (build, overrides)) in _pages.entries) {
    testWidgets('$name: no layout errors at any brief size, populated', (
      tester,
    ) async {
      final failures = <String>[];
      for (final size in _briefSizes) {
        final errors = await pumpAtSize(
          tester,
          size,
          build(),
          overrides: overrides,
        );
        for (final e in errors) {
          failures.add('$size: ${shortError(e)}');
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }
}
