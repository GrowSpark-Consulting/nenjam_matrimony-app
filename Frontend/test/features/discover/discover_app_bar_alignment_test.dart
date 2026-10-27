import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/services/location/device_location_service.dart';
import 'package:nenjam_matrimony/core/services/location/location_providers.dart';
import 'package:nenjam_matrimony/core/theme/app_theme.dart';
import 'package:nenjam_matrimony/core/widgets/avatars/app_avatars.dart';
import 'package:nenjam_matrimony/features/discover/domain/entities/discover_feed_entity.dart';
import 'package:nenjam_matrimony/features/discover/presentation/pages/discover_page.dart';
import 'package:nenjam_matrimony/features/discover/presentation/providers/discover_providers.dart';
import 'package:nenjam_matrimony/features/nearby/domain/repositories/nearby_repository.dart';
import 'package:nenjam_matrimony/features/nearby/presentation/providers/nearby_providers.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'package:nenjam_matrimony/features/profile_completion/domain/completion_recommendation.dart';
import 'package:nenjam_matrimony/features/profile_completion/presentation/widgets/complete_profile_card.dart';
import 'package:nenjam_matrimony/features/profile_photos/domain/models/user_photo.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/providers/photo_providers.dart';
import 'package:nenjam_matrimony/features/registration/data/repositories/registration_repository.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The Discover app bar's brand row lines up with the feed below it.
///
/// The app-wide AppBarTheme centres titles. Discover's title is a
/// start-aligned avatar + wordmark row, and centring it squeezed the row by
/// the actions' width and shifted it right, so the avatar sat well inside
/// the left edge of the Complete Your Profile card while the bell still
/// matched its right edge. Pumped with the real [AppTheme.light] on purpose:
/// under Flutter's default theme the title is never centred off iOS, which
/// is how this slipped past the other Discover tests.

const _emptyFeed = DiscoverFeedEntity(
  stories: [],
  profileCompletionPercent: 0,
  aiRecommended: [],
  recentlyJoined: [],
  verifiedProfiles: [],
  nearYou: [],
  premiumMembers: [],
  fallbackReason: 'NO_MATCHES',
);

Map<String, dynamic> _draft() => <String, dynamic>{
  'completionPercentage': 65,
  'completionBreakdown': const [
    {'id': 'registration', 'weight': 60, 'isComplete': true, 'wizardStep': 0},
  ],
  'registrationComplete': true,
  'recommendations': [
    for (final (key, step) in const [
      (CompletionCardKeys.aboutFamily, 7),
      (CompletionCardKeys.horoscope, 8),
      (CompletionCardKeys.psychology, 9),
    ])
      <String, dynamic>{
        'key': key,
        'isComplete': false,
        'isDismissed': false,
        'affectsScore': false,
        'wizardStep': step,
      },
  ],
};

class _SilentLocationService implements DeviceLocationService {
  @override
  Future<LocationResult?> checkPermissionOnly() async =>
      const LocationPermissionDenied();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyNearbyRepository implements NearbyRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRegistrationRepository implements RegistrationRepository {
  @override
  Future<Map<String, dynamic>> getDraft() async => <String, dynamic>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePhotosController extends PhotosController {
  @override
  Future<List<UserPhoto>> build() async => const <UserPhoto>[];
}

Future<void> _pumpDiscover(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        discoverFeedProvider.overrideWith((ref) async => _emptyFeed),
        profileDraftResponseProvider.overrideWith((ref) async => _draft()),
        registrationRepositoryProvider.overrideWithValue(
          _FakeRegistrationRepository(),
        ),
        deviceLocationServiceProvider.overrideWithValue(
          _SilentLocationService(),
        ),
        nearbyRepositoryProvider.overrideWithValue(_EmptyNearbyRepository()),
        myPhotosProvider.overrideWith(_FakePhotosController.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DiscoverPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Phone, the 750dp window from the bug report, and a tablet landscape —
  // all below the 1200dp width where the inbox panel joins the layout.
  for (final size in const [Size(390, 844), Size(750, 900), Size(1024, 768)]) {
    testWidgets('${size.width.toInt()}dp: avatar starts on the card edge', (
      tester,
    ) async {
      await _pumpDiscover(tester, size);

      final card = tester.getRect(
        find
            .descendant(
              of: find.byType(CompleteProfileCard),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final avatar = tester.getRect(
        find
            .descendant(
              of: find.byType(AppBar),
              matching: find.byType(NmCircleAvatar),
            )
            .first,
      );
      final bell = tester.getRect(
        find.byIcon(Icons.notifications_none_rounded),
      );

      expect(avatar.left, moreOrLessEquals(card.left, epsilon: 1));
      // The right side already matched; it must stay that way.
      expect(bell.right, moreOrLessEquals(card.right, epsilon: 1));
    });
  }
}
