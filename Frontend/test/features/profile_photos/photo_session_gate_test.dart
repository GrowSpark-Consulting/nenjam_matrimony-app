import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/authentication/data/models/auth_user.dart';
import 'package:nenjam_matrimony/features/authentication/data/repositories/auth_repository_impl.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/auth_token_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/profile_photos/data/repositories/photo_repository.dart';
import 'package:nenjam_matrimony/features/profile_photos/domain/models/user_photo.dart';
import 'package:nenjam_matrimony/features/profile_photos/presentation/providers/photo_providers.dart';

/// **No photo request goes out without a session.**
///
/// Onboarding's Add Photos step is reached BEFORE the member has a
/// credential: the session is minted two screens later, at OTP. Every photo
/// call made there went out unauthenticated, the backend answered 401, and
/// the interceptor's 401 recovery signed the member out mid-signup. The field
/// log read:
///
///   token lookup ← hasToken=false
///   PhotoApiException(401): You are not signed in.
///
/// The read path needed the same guard the write path already had — building
/// the provider fired `GET /profiles/me/photos` on its own, before any
/// mutation was attempted.
void main() {
  ProviderContainer containerWith({
    required bool signedIn,
    required _RecordingPhotoRepository repo,
  }) {
    final container = ProviderContainer(
      overrides: [
        photoRepositoryProvider.overrideWithValue(repo),
        authTokenServiceProvider
            .overrideWithValue(_StubTokenService(signedIn: signedIn)),
        authRepositoryProvider.overrideWithValue(_StubAuthRepository()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('signed out', () {
    test('building the provider does not call the photos endpoint', () async {
      final repo = _RecordingPhotoRepository();
      final container = containerWith(signedIn: false, repo: repo);

      final photos = await container.read(myPhotosProvider.future);

      expect(photos, isEmpty);
      expect(
        repo.fetchCalls,
        0,
        reason: 'a doomed GET is what triggered the 401 sign-out',
      );
    });

    test('upload is refused with a 401 and never reaches the network',
        () async {
      final repo = _RecordingPhotoRepository();
      final container = containerWith(signedIn: false, repo: repo);
      await container.read(myPhotosProvider.future);

      await container
          .read(myPhotosProvider.notifier)
          .upload(XFile('/tmp/photo.jpg'), isPrimary: true);

      final state = container.read(myPhotosProvider);
      expect(state.hasError, isTrue, reason: '401 must not be swallowed');
      expect(
        state.error,
        isA<PhotoApiException>().having((e) => e.statusCode, 'status', 401),
      );
      expect(repo.uploadCalls, 0);
    });
  });

  group('signed in', () {
    test('building the provider fetches the gallery', () async {
      final repo = _RecordingPhotoRepository();
      final container = containerWith(signedIn: true, repo: repo);

      final photos = await container.read(myPhotosProvider.future);

      expect(repo.fetchCalls, 1);
      expect(photos, hasLength(1));
    });

    test('upload posts, then re-reads to prove the photo persisted', () async {
      final repo = _RecordingPhotoRepository();
      final container = containerWith(signedIn: true, repo: repo);
      await container.read(myPhotosProvider.future);

      await container
          .read(myPhotosProvider.notifier)
          .upload(XFile('/tmp/photo.jpg'), isPrimary: true);

      final state = container.read(myPhotosProvider);
      expect(state.hasError, isFalse);
      expect(repo.uploadCalls, 1);
      expect(repo.lastIsPrimary, isTrue);
      // The re-read is the step that proves the photo is visible to a fresh
      // GET rather than trusting the POST body.
      expect(repo.fetchCalls, 2);
    });

    test('a second tap mid-upload does not upload twice', () async {
      final repo = _RecordingPhotoRepository(uploadDelay: true);
      final container = containerWith(signedIn: true, repo: repo);
      await container.read(myPhotosProvider.future);

      final notifier = container.read(myPhotosProvider.notifier);
      await Future.wait([
        notifier.upload(XFile('/tmp/a.jpg')),
        notifier.upload(XFile('/tmp/a.jpg')),
      ]);

      expect(repo.uploadCalls, 1);
    });
  });
}

class _RecordingPhotoRepository implements PhotoRepository {
  _RecordingPhotoRepository({this.uploadDelay = false});

  final bool uploadDelay;
  int fetchCalls = 0;
  int uploadCalls = 0;
  bool? lastIsPrimary;

  static const _photo = UserPhoto(
    id: 'p1',
    cdnUrl: 'https://cdn.example.test/p1.jpg',
    isPrimary: true,
    order: 0,
    isApproved: true,
  );

  @override
  Future<List<UserPhoto>> fetchPhotos() async {
    fetchCalls++;
    return const [_photo];
  }

  @override
  Future<UserPhoto> upload(XFile file, {bool? isPrimary}) async {
    uploadCalls++;
    lastIsPrimary = isPrimary;
    if (uploadDelay) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return _photo;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubTokenService implements AuthTokenService {
  _StubTokenService({required this.signedIn});

  final bool signedIn;

  @override
  Future<String?> getFirebaseToken({bool forceRefresh = false}) async =>
      signedIn ? 'stub-id-token' : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubAuthRepository implements FirebaseAuthRepository {
  // uid is diagnostics-only in photoUploadSession — the token decides whether
  // a session exists. It must still ANSWER, though: an exception here is
  // caught and read as "signed out", which is exactly the failure this file
  // exists to catch.
  @override
  AuthUser? get currentAuthUser => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
