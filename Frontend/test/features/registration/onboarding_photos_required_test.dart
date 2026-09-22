import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/data/models/auth_user.dart';
import 'package:nenjam_matrimony/features/authentication/data/repositories/auth_repository_impl.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/auth_token_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/profile/domain/models/profile.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_providers.dart';
import 'package:nenjam_matrimony/features/profile_photos/data/repositories/photo_repository.dart';
import 'package:nenjam_matrimony/features/profile_photos/domain/models/user_photo.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/providers/photo_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_photos_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/features/registration/presentation/utils/onboarding_draft_gate.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

import 'onboarding_test_support.dart';

/// At least one profile photo is required before registration can continue.
///
/// Two things enforce that, and both are covered here: the Add Photos step's
/// own Continue gate, and the shared draft gate that decides where a resumed
/// signup re-enters onboarding — which used to walk income → about, so a
/// member who skipped photos resumed permanently past the step.

UserPhoto _photo({String id = 'p1', bool isPrimary = true, int order = 0}) =>
    UserPhoto(
      id: id,
      cdnUrl: 'https://bucket.s3.ap-south-1.amazonaws.com/p/$id.jpg?X-Amz=sig',
      isPrimary: isPrimary,
      order: order,
      isApproved: false,
    );

/// Stands in for the backend. `implements` + [noSuchMethod] follows
/// onboarding_test_support.dart: only the calls this screen makes are
/// stubbed, so a new endpoint fails loudly rather than silently doing
/// nothing.
class _FakePhotoRepository implements PhotoRepository {
  _FakePhotoRepository({List<UserPhoto>? stored})
      : stored = stored ?? <UserPhoto>[];

  List<UserPhoto> stored;

  @override
  Future<List<UserPhoto>> fetchPhotos() async => stored;

  /// Returns the authoritative remaining list, as the real repository does —
  /// that return value is what [PhotosController] republishes.
  @override
  Future<List<UserPhoto>> delete(String id) async {
    stored = stored.where((p) => p.id != id).toList();
    return stored;
  }

  @override
  Future<UserPhoto> upload(XFile file, {bool? isPrimary}) async {
    final created = _photo(
      id: 'p${stored.length + 1}',
      isPrimary: isPrimary ?? stored.isEmpty,
      order: stored.length,
    );
    stored = [...stored, created];
    return created;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Signed in, so [PhotosController.build] actually fetches rather than
/// short-circuiting to an empty gallery.
class _TokenService implements AuthTokenService {
  @override
  Future<String?> getFirebaseToken({bool forceRefresh = false}) async =>
      'a-token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubAuthRepository implements FirebaseAuthRepository {
  @override
  AuthUser? get currentAuthUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_FakePhotoRepository repo) {
  final container = ProviderContainer(
    overrides: [
      photoRepositoryProvider.overrideWithValue(repo),
      authTokenServiceProvider.overrideWithValue(_TokenService()),
      authRepositoryProvider.overrideWithValue(_StubAuthRepository()),
      // A successful mutation invalidates myProfileProvider. Left real that
      // reaches the network and leaves a pending timer the binding fails on;
      // these tests are about the photo gate, so park it.
      myProfileProvider.overrideWith((ref) => Completer<Profile>().future),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// The photo step plus the screen it may not reach, so a test can assert on
/// where navigation actually landed rather than only on the button.
GoRouter _router() => GoRouter(
      initialLocation: RouteNames.onboardingPhotos,
      routes: [
        GoRoute(
          path: RouteNames.onboardingPhotos,
          builder: (_, __) => const OnboardingPhotosPage(),
        ),
        GoRoute(
          path: RouteNames.onboardingAbout,
          builder: (_, __) => const Scaffold(body: Text('ABOUT STEP')),
        ),
      ],
    );

/// The Continue control, found by its label rather than by index so it
/// survives the gallery/camera buttons moving.
Finder _continueButton(WidgetTester tester) {
  final l10n = AppLocalizations.of(
    tester.element(find.byType(OnboardingPhotosPage)),
  );
  return find.widgetWithText(TextButton, l10n.commonContinue);
}

bool _continueEnabled(WidgetTester tester) =>
    tester.widget<TextButton>(_continueButton(tester)).onPressed != null;

Future<void> _pumpStep(
  WidgetTester tester,
  ProviderContainer container,
) async {
  useTallSurface(tester);
  await tester.pumpWidget(harness(container, _router()));
  await tester.pumpAndSettle();
}

/// A draft with every step before photos answered, so the only thing the
/// gate can still object to is the photo requirement itself.
ProfileDraft _draftUpToPhotos({PhotoGallery? gallery}) => ProfileDraft(
      basicDetails: BasicDetails(
        profileCreatedFor: 'Self',
        gender: 'Male',
        firstName: 'Arjun',
        lastName: 'Krishnan',
        dob: DateTime(1998, 8, 15),
        maritalStatus: 'Never Married',
      ),
      religionDetails: const ReligionDetails(
        religion: 'HINDU',
        community: 'HINDU-IYER',
      ),
      locationDetails: const LocationDetails(
        country: 'IN',
        state: 'IN-GJ',
        city: 'IN-GJ-BHAVNAGAR',
      ),
      physicalDetails: const PhysicalDetails(height: '5ft 9in'),
      educationDetails: const EducationDetails(
        qualification: 'Bachelors',
        annualIncome: '5-10 LPA',
      ),
      lifestyleDetails: const LifestyleDetails(aboutMe: 'Hello there.'),
      photoGallery: gallery ?? const PhotoGallery(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Add Photos step — Continue gate', () {
    testWidgets('0 photos → Continue is disabled', (tester) async {
      final container = _container(_FakePhotoRepository());
      await _pumpStep(tester, container);

      expect(_continueButton(tester), findsOneWidget);
      expect(
        _continueEnabled(tester),
        isFalse,
        reason: 'with no photos the member must stay on this step',
      );
    });

    testWidgets('0 photos → no Add Later / Skip escape is offered',
        (tester) async {
      final container = _container(_FakePhotoRepository());
      await _pumpStep(tester, container);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(OnboardingPhotosPage)),
      );
      expect(
        find.text(l10n.onboardingPhotosLater),
        findsNothing,
        reason: '"Add Photos Later" would bypass the requirement',
      );
      // Nothing else on the step may act as a skip either.
      expect(find.textContaining('Skip'), findsNothing);
    });

    testWidgets('0 photos → tapping Continue does not navigate',
        (tester) async {
      final container = _container(_FakePhotoRepository());
      await _pumpStep(tester, container);

      await tester.tap(_continueButton(tester), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('ABOUT STEP'), findsNothing);
      expect(find.byType(OnboardingPhotosPage), findsOneWidget);
    });

    testWidgets('1 photo → Continue is enabled and advances', (tester) async {
      final container = _container(
        _FakePhotoRepository(stored: [_photo()]),
      );
      await _pumpStep(tester, container);

      expect(_continueEnabled(tester), isTrue);

      await tester.tap(_continueButton(tester));
      await tester.pumpAndSettle();
      expect(find.text('ABOUT STEP'), findsOneWidget);
    });

    testWidgets('multiple photos → Continue is enabled', (tester) async {
      final container = _container(
        _FakePhotoRepository(stored: [
          _photo(id: 'p1'),
          _photo(id: 'p2', isPrimary: false, order: 1),
          _photo(id: 'p3', isPrimary: false, order: 2),
        ]),
      );
      await _pumpStep(tester, container);

      expect(_continueEnabled(tester), isTrue);
    });

    testWidgets('deleting the only photo disables Continue again',
        (tester) async {
      final repo = _FakePhotoRepository(stored: [_photo(id: 'p1')]);
      final container = _container(repo);
      await _pumpStep(tester, container);

      expect(_continueEnabled(tester), isTrue);

      // Delete through the real controller — the same path the photo manager
      // uses — so the gate is proven to track live state, not a first build.
      await container.read(myPhotosProvider.notifier).delete('p1');
      await tester.pumpAndSettle();

      expect(
        _continueEnabled(tester),
        isFalse,
        reason: 'removing the last photo must re-block the step',
      );
      await tester.tap(_continueButton(tester), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('ABOUT STEP'), findsNothing);
    });

    testWidgets('a draft-staged (pre-session) photo also enables Continue',
        (tester) async {
      // Before OTP there is no session, so photos are staged in the draft
      // rather than uploaded. They count just the same.
      final container = _container(_FakePhotoRepository());
      container.read(registrationProvider.notifier).updatePhotoGallery(
            const PhotoGallery(primaryPhotoPath: '/tmp/staged.jpg'),
          );
      await _pumpStep(tester, container);

      expect(_continueEnabled(tester), isTrue);
    });
  });

  group('Resume gate — the bypass that skipped the step entirely', () {
    test('a pre-session draft with no staged photos resumes at the photo step',
        () {
      expect(
        firstUnansweredOnboardingStep(
          _draftUpToPhotos(),
          gatePendingPhotos: true,
        ),
        RouteNames.onboardingPhotos,
      );
    });

    test('a saved draft with one staged photo stays completable', () {
      expect(
        firstUnansweredOnboardingStep(
          _draftUpToPhotos(
            gallery: const PhotoGallery(primaryPhotoPath: '/tmp/a.jpg'),
          ),
          gatePendingPhotos: true,
        ),
        isNull,
        reason: 'a restored draft that already has a photo is done',
      );
    });

    test('a saved draft with several staged photos stays completable', () {
      expect(
        firstUnansweredOnboardingStep(
          _draftUpToPhotos(
            gallery: const PhotoGallery(
              primaryPhotoPath: '/tmp/a.jpg',
              galleryPaths: ['/tmp/b.jpg', '/tmp/c.jpg'],
            ),
          ),
          gatePendingPhotos: true,
        ),
        isNull,
      );
    });

    test(
        'a restored BACKEND draft is never gated on photos, however empty its '
        'gallery', () {
      // The regression this guards: `photoGallery` is a local staging queue
      // that the backend never populates, so an established member with
      // uploaded photos restores a draft with an empty gallery. Gating that
      // sent every such member to the photo step instead of the app.
      expect(
        firstUnansweredOnboardingStep(_draftUpToPhotos()),
        isNull,
        reason: 'the default must not gate a server-restored draft on photos',
      );
    });

    test('the photo gate runs after income and before about', () {
      // Order matters: gating before income would strand a member on photos
      // with earlier answers still missing.
      final noIncome = _draftUpToPhotos().copyWith(
        educationDetails: const EducationDetails(qualification: 'Bachelors'),
      );
      expect(
        firstUnansweredOnboardingStep(noIncome, gatePendingPhotos: true),
        RouteNames.onboardingIncome,
      );

      final noAbout = _draftUpToPhotos(
        gallery: const PhotoGallery(primaryPhotoPath: '/tmp/a.jpg'),
      ).copyWith(lifestyleDetails: const LifestyleDetails(aboutMe: ''));
      expect(
        firstUnansweredOnboardingStep(noAbout, gatePendingPhotos: true),
        RouteNames.onboardingAbout,
      );
    });
  });
}
