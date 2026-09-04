import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/widgets/images/sized_network_photo.dart';
import 'package:nenjam_matrimony/features/authentication/data/models/auth_user.dart';
import 'package:nenjam_matrimony/features/authentication/data/repositories/auth_repository_impl.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/auth_token_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/profile/domain/models/profile.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_providers.dart';
import 'package:nenjam_matrimony/features/profile/presentation/widgets/photo_gallery_card.dart';
import 'package:nenjam_matrimony/features/profile_photos/data/repositories/photo_repository.dart';
import 'package:nenjam_matrimony/features/profile_photos/domain/models/user_photo.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/providers/photo_providers.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

/// The photo a successful upload comes back as: a presigned GET against the
/// private bucket, which is the only URL shape the UI is ever given.
const _remoteUrl =
    'https://bucket.s3.ap-south-1.amazonaws.com/profile-photos/u1/a.jpg'
    '?X-Amz-Signature=abc';

/// What the member picked during Create Account, before it was uploaded.
/// Nothing may ever render this.
const _localCachePath = '/data/user/0/com.nenjam/cache/crop.jpg';

UserPhoto _photo({
  String id = 'p1',
  String url = _remoteUrl,
  bool isPrimary = true,
  int order = 0,
}) =>
    UserPhoto(
      id: id,
      cdnUrl: url,
      isPrimary: isPrimary,
      order: order,
      isApproved: false,
    );

/// Stands in for the backend. `implements` + [noSuchMethod] follows
/// onboarding_test_support.dart: only the calls this flow makes are stubbed,
/// so a new endpoint fails loudly here rather than silently doing nothing.
class _FakePhotoRepository implements PhotoRepository {
  _FakePhotoRepository({this.failUpload = false});

  final bool failUpload;
  List<UserPhoto> stored = <UserPhoto>[];
  int fetchCount = 0;
  final List<XFile> uploaded = <XFile>[];

  @override
  Future<List<UserPhoto>> fetchPhotos() async {
    fetchCount++;
    return stored;
  }

  @override
  Future<UserPhoto> upload(XFile file, {bool? isPrimary}) async {
    if (failUpload) throw PhotoApiException(500, 'upload failed');
    uploaded.add(file);
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

/// Mutable so a test can reproduce Create Account's ordering: the photo step
/// runs signed out, OTP mints the session, and everything after it is signed
/// in — the same object, flipped mid-test.
class _TokenService implements AuthTokenService {
  _TokenService({required this.signedIn});

  bool signedIn;

  @override
  Future<String?> getFirebaseToken({bool forceRefresh = false}) async =>
      signedIn ? 'a-token' : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubAuthRepository implements FirebaseAuthRepository {
  /// Read only for the diagnostic UID in PhotoTrace; the session decision
  /// itself is the token's.
  @override
  AuthUser? get currentAuthUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container({
  required _FakePhotoRepository repo,
  _TokenService? tokens,
}) {
  final container = ProviderContainer(
    overrides: [
      photoRepositoryProvider.overrideWithValue(repo),
      authTokenServiceProvider
          .overrideWithValue(tokens ?? _TokenService(signedIn: true)),
      authRepositoryProvider.overrideWithValue(_StubAuthRepository()),
      // A successful mutation invalidates myProfileProvider so the profile
      // screen's embedded photo list and completion % refresh with it. Left
      // real, that reaches for the network: `ref.invalidate` instantiates the
      // provider, which issues `GET /profiles/me` through the live ApiClient
      // and leaves a pending timer the test binding then fails on. These
      // tests are about the photo provider, so park it — pending forever,
      // never read, no request.
      myProfileProvider.overrideWith((ref) => Completer<Profile>().future),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _wrap(ProviderContainer container, Widget child) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('upload refreshes the shared photo provider', () {
    test('a successful Create Account upload publishes the stored photo',
        () async {
      final repo = _FakePhotoRepository();
      final container = _container(repo: repo);

      // The queue drain at OTP calls exactly this.
      await container
          .read(myPhotosProvider.notifier)
          .upload(XFile.fromData(Uint8List.fromList([1, 2, 3])),
              isPrimary: true);

      final photos = container.read(myPhotosProvider).valueOrNull;
      expect(photos, hasLength(1));
      expect(photos!.single.cdnUrl, _remoteUrl);
      expect(repo.fetchCount, greaterThanOrEqualTo(1),
          reason: 'upload re-reads the list rather than trusting the POST '
              'body, which is what proves the photo is really persisted');
      // And the derivation every avatar in the app reads resolves to it.
      expect(container.read(myPrimaryPhotoUrlProvider), _remoteUrl);
    });

    test('a failed upload leaves the provider in an error state, not empty',
        () async {
      final repo = _FakePhotoRepository(failUpload: true);
      final container = _container(repo: repo);

      await container
          .read(myPhotosProvider.notifier)
          .upload(XFile.fromData(Uint8List.fromList([1])), isPrimary: true);

      expect(container.read(myPhotosProvider).hasError, isTrue,
          reason: 'a failure must not be reported as "no photos"');
    });

    test('the primary photo is the one chosen, not merely the first',
        () async {
      final repo = _FakePhotoRepository()
        ..stored = [
          _photo(id: 'a', url: 'https://example.com/a.jpg', isPrimary: false),
          _photo(id: 'b', url: 'https://example.com/b.jpg', isPrimary: true,
              order: 1),
        ];
      final container = _container(repo: repo);
      await container.read(myPhotosProvider.future);

      expect(container.read(myPrimaryPhotoUrlProvider),
          'https://example.com/b.jpg');
    });
  });

  group('provider invalidation clears stale empty state', () {
    test('a photo added after a signed-out build appears once refetched',
        () async {
      // Reproduces the Create Account ordering: Add Photos runs before the
      // credential exists, so the provider first builds with no session and
      // reports an empty gallery.
      final repo = _FakePhotoRepository();
      final tokens = _TokenService(signedIn: false);
      final container = _container(repo: repo, tokens: tokens);

      expect(await container.read(myPhotosProvider.future), isEmpty);
      expect(repo.fetchCount, 0,
          reason: 'no session — there is nothing to ask the backend for');

      // OTP mints the session and the photo lands on the backend.
      tokens.signedIn = true;
      repo.stored = [_photo()];

      // What main.dart does on the uid change. Without it the empty list
      // above would stand for the rest of the process.
      container.invalidate(myPhotosProvider);

      final photos = await container.read(myPhotosProvider.future);
      expect(photos.single.cdnUrl, _remoteUrl);
    });
  });

  group('My Profile photo section', () {
    testWidgets('renders the stored remote cdnUrl', (tester) async {
      final repo = _FakePhotoRepository()..stored = [_photo()];
      final container = _container(repo: repo);
      await container.read(myPhotosProvider.future);

      // Exactly what ProfilePage builds the section with.
      final urls = container
          .read(myPhotosProvider)
          .valueOrNull!
          .map((p) => p.cdnUrl)
          .toList();

      await tester.pumpWidget(
        _wrap(container, NmPhotoGalleryCard(photoUrls: urls)),
      );
      await tester.pump();

      final photo = tester.widget<NmSizedNetworkPhoto>(
        find.byType(NmSizedNetworkPhoto),
      );
      expect(photo.url, _remoteUrl);
    });

    testWidgets('shows the existing placeholder when there are no photos',
        (tester) async {
      final repo = _FakePhotoRepository();
      final container = _container(repo: repo);
      await container.read(myPhotosProvider.future);

      await tester.pumpWidget(
        _wrap(container, const NmPhotoGalleryCard(photoUrls: [])),
      );
      await tester.pump();

      // The dashed "ADD" tile is the placeholder; no image is attempted.
      expect(find.byType(NmSizedNetworkPhoto), findsNothing);
      expect(find.text('ADD'), findsOneWidget);
    });

    test('uploading a local cache file yields only the remote URL', () async {
      final repo = _FakePhotoRepository();
      final container = _container(repo: repo);

      // Exactly what the OTP-step drain does: hand the controller the cropped
      // file sitting in the cache directory.
      await container.read(myPhotosProvider.notifier).upload(
            XFile(_localCachePath),
            isPrimary: true,
          );

      final urls = container
          .read(myPhotosProvider)
          .valueOrNull!
          .map((p) => p.cdnUrl)
          .toList();
      // The path the file was read from never becomes the photo's identity —
      // the OS reaps that cache entry, and a UI still pointed at it would
      // render a broken tile forever.
      expect(urls, isNot(contains(_localCachePath)));
      expect(urls.single, _remoteUrl);
      expect(urls.single, startsWith('https://'));
    });

    testWidgets('renders no local file path, only the remote URL',
        (tester) async {
      final repo = _FakePhotoRepository()..stored = [_photo()];
      final container = _container(repo: repo);
      final urls = (await container.read(myPhotosProvider.future))
          .map((p) => p.cdnUrl)
          .toList();

      await tester.pumpWidget(
        _wrap(container, NmPhotoGalleryCard(photoUrls: urls)),
      );
      await tester.pump();

      final photo = tester.widget<NmSizedNetworkPhoto>(
        find.byType(NmSizedNetworkPhoto),
      );
      expect(photo.url, _remoteUrl);
      expect(photo.url, isNot(_localCachePath));
      expect(photo.url, isNot(startsWith('/')));
    });
  });

  group('Edit Profile and My Profile agree', () {
    test('both read the same provider, so they cannot disagree', () async {
      // PhotoManagerSection (Edit Profile) and ProfilePage's gallery card
      // are both fed from myPhotosProvider — this pins that they resolve to
      // one and the same list.
      final repo = _FakePhotoRepository()..stored = [_photo()];
      final container = _container(repo: repo);

      final editProfileSees = await container.read(myPhotosProvider.future);
      final myProfileSees =
          container.read(myPhotosProvider).valueOrNull!;

      expect(editProfileSees, same(myProfileSees));
      expect(myProfileSees.single.cdnUrl, _remoteUrl);
      expect(repo.fetchCount, 1, reason: 'one shared fetch, not one each');
    });
  });
}
