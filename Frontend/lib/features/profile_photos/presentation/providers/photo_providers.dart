import 'package:cross_file/cross_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../../../core/utils/photo_trace.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/repositories/photo_repository.dart';
import '../../domain/models/user_photo.dart';
import '../../../verification/presentation/providers/face_verification_providers.dart';

/// Backend-backed photo repository, wired to the shared authenticated
/// [apiClientProvider] so every request carries the Firebase ID token.
final photoRepositoryProvider = Provider<PhotoRepository>(
  (ref) => PhotoRepository(ref.watch(apiClientProvider)),
);

/// The signed-in user's photos (0-6), newest ordering from the backend, each
/// with a fresh presigned URL. Read-only consumers (profile dashboard, review
/// screen) watch this; mutations go through [PhotosController], which keeps
/// this provider's cache in sync.
final myPhotosProvider =
    AsyncNotifierProvider<PhotosController, List<UserPhoto>>(
      PhotosController.new,
    );

/// The signed-in user's current avatar URL — the primary photo's `cdnUrl`,
/// falling back to the first photo if none is flagged primary, or `null`
/// with no photos yet. The single derivation every current-user avatar in
/// the app (drawer, Discover app bar, profile hero) should read instead of
/// each re-implementing the same "pick primary, else first" lookup —
/// Riverpod only notifies watchers when this resolved value actually
/// changes, so unrelated [myPhotosProvider] state churn (e.g. a reorder's
/// loading tick) doesn't cause extra rebuilds downstream.
final myPrimaryPhotoUrlProvider = Provider<String?>((ref) {
  final photos = ref.watch(myPhotosProvider).valueOrNull ?? const <UserPhoto>[];
  if (photos.isEmpty) return null;
  return photos
      .firstWhere((p) => p.isPrimary, orElse: () => photos.first)
      .cdnUrl;
});

/// Whether a Firebase ID token is actually obtainable right now, and the UID
/// it belongs to (for diagnostics — never the token itself).
///
/// Waits out the post-launch window in which Firebase has not yet restored
/// `currentUser` rather than reading it synchronously, so an ordinary cold
/// start *waits* instead of reporting "signed out". This is the one session
/// check the photo feature has: [PhotosController] gates every read and write
/// on it, and so does onboarding's Add Photos step, which is the one screen
/// that can be reached before any credential exists.
/// Reads a provider. `Ref` (inside a provider) and `WidgetRef` (inside a
/// widget) share no supertype but both expose exactly this, so taking the
/// tear-off lets one implementation serve both callers.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

Future<({bool ok, String? uid})> photoUploadSession(ProviderReader read) async {
  PhotoTrace.step('token lookup →');
  try {
    final uid = read(authRepositoryProvider).currentAuthUser?.uid;
    final token = await read(authTokenServiceProvider).getFirebaseToken();
    final ok = token != null && token.isNotEmpty;
    // Never log the token; its presence and the UID are what diagnose this.
    PhotoTrace.step('token lookup ←', {'hasToken': ok, 'uid': uid});
    return (ok: ok, uid: uid);
  } catch (error) {
    PhotoTrace.fail('token lookup', error);
    return (ok: false, uid: null);
  }
}

/// Owns photo state and every mutation. Each mutation optimistically flips the
/// provider into a loading state, calls the backend, and republishes the
/// authoritative list the backend returns — so the UI (wizard step, profile
/// dashboard, edit profile) refreshes immediately and identically everywhere
/// this provider is watched.
class PhotosController extends AsyncNotifier<List<UserPhoto>> {
  PhotoRepository get _repo => ref.read(photoRepositoryProvider);

  @override
  Future<List<UserPhoto>> build() async {
    // Onboarding's Add Photos step is reached BEFORE the member has a
    // credential — the session is minted two screens later, at OTP. Building
    // this provider there fired `GET /profiles/me/photos` unauthenticated;
    // the backend answered 401, whose JSON error body then failed Dio's
    // `List<dynamic>` cast, and the interceptor's 401 recovery signed the
    // member out mid-signup. There is nothing to fetch without a session, so
    // report an empty gallery instead of asking.
    if (!(await photoUploadSession(ref.read)).ok) {
      PhotoTrace.step('no session — skipping initial photo fetch');
      return const <UserPhoto>[];
    }
    return _repo.fetchPhotos();
  }

  /// True while a mutation (or an explicit refresh) is in flight.
  ///
  /// Every mutation below is reached from a tap, and the photo UI stays
  /// interactive during one — the gallery keeps the previous list visible
  /// under a spinner rather than unmounting. A second tap that lands before
  /// the first completes would issue a second upload (two copies of the same
  /// photo, and the 6-photo cap consumed twice as fast) or a second delete
  /// (the first already removed the row, so the retry 404s and surfaces an
  /// error for an operation that actually succeeded). Serialising here rather
  /// than in each widget keeps every call site — wizard step, edit profile,
  /// drawer sheet — covered by the same rule.
  bool _busy = false;

  /// Runs [op], publishing its result as the authoritative photo list.
  ///
  /// [syncProfile] re-reads `GET /profiles/me` on success. Photos are their
  /// own backend resource, but the profile response embeds them AND the
  /// backend-computed completion percentage, which moves by 12% the moment a
  /// member's first photo lands or their last one goes. Without this the
  /// registration success screen and anything else reading [myProfileProvider]
  /// kept serving the pre-upload snapshot — the case its own doc comment
  /// described as "after photo mutations once those exist".
  Future<void> _run(
    Future<List<UserPhoto>> Function() op, {
    bool syncProfile = true,
    bool requireAuth = true,
  }) async {
    if (_busy) {
      PhotoTrace.step('ignored — a photo operation is already in flight');
      return;
    }
    _busy = true;
    state = const AsyncValue<List<UserPhoto>>.loading().copyWithPrevious(state);
    try {
      // Never start a write without a usable session.
      //
      // Sending it anyway produced the worst possible outcome: the request
      // went out unauthenticated, the backend answered 401, and the
      // interceptor's recovery signed the member out mid-upload. Asking for
      // the token first also waits out the startup window in which Firebase
      // has not yet restored `currentUser` (see AuthTokenService), so the
      // ordinary cold-start case now *waits* rather than failing.
      if (requireAuth && !await _hasSession()) {
        state = AsyncValue<List<UserPhoto>>.error(
          PhotoApiException(401, 'You are not signed in.'),
          StackTrace.current,
        ).copyWithPrevious(state);
        return;
      }
      state = await AsyncValue.guard(op);
    } finally {
      _busy = false;
    }
    // Only on success: a failed upload must leave the profile's cached photo
    // list exactly as it was, not refetch as though something had changed.
    if (syncProfile && !state.hasError) {
      ref.invalidate(myProfileProvider);
    }
    PhotoTrace.step('provider updated', {
      'hasError': state.hasError,
      'count': state.valueOrNull?.length,
      'error': state.error,
    });
  }

  /// Whether a Firebase ID token is actually obtainable right now. Waits out
  /// the post-launch restore window rather than reading `currentUser`
  /// synchronously — see AuthTokenService.getFirebaseToken.
  Future<bool> _hasSession() async => (await photoUploadSession(ref.read)).ok;

  /// Re-fetches from the backend (e.g. pull-to-refresh or retry after error).
  Future<void> refresh() {
    PhotoTrace.begin('refresh');
    return _run(
      _repo.fetchPhotos,
      syncProfile: false,
    ).whenComplete(() => PhotoTrace.end('refresh'));
  }

  Future<void> upload(XFile file, {bool? isPrimary}) {
    PhotoTrace.begin('upload isPrimary=$isPrimary');
    return _run(() async {
      await _repo.upload(file, isPrimary: isPrimary);
      // Re-read rather than trusting the POST body: this is what proves the
      // photo is actually persisted and visible to a fresh GET, which is the
      // exact step the reported bug turned on.
      return _repo.fetchPhotos();
    }).whenComplete(() => PhotoTrace.end('upload'));
  }

  Future<void> replace(String id, XFile file) {
    PhotoTrace.begin('replace $id');
    return _run(() async {
      await _repo.replace(id, file);
      return _repo.fetchPhotos();
    }).whenComplete(() {
      PhotoTrace.end('replace');
      _invalidateFaceVerificationStatus();
    });
  }

  Future<void> delete(String id) {
    PhotoTrace.begin('delete $id');
    return _run(() => _repo.delete(id)).whenComplete(() {
      PhotoTrace.end('delete');
      _invalidateFaceVerificationStatus();
    });
  }

  Future<void> reorder(List<String> orderedIds) =>
      _run(() => _repo.reorder(orderedIds));

  Future<void> setPrimary(String id) => _run(
    () => _repo.setPrimary(id),
  ).whenComplete(_invalidateFaceVerificationStatus);

  /// The three mutations above can each change which photo is primary
  /// (replace keeps the same photo id but a new S3 key; delete can remove
  /// the primary photo; setPrimary moves it outright) — any of those revokes
  /// a face verification server-side (see
  /// docs/development/selfie-verification-frontend-handoff.md §6.1), so the
  /// cached status must be refetched rather than left showing a stale
  /// "verified" badge.
  void _invalidateFaceVerificationStatus() {
    ref.invalidate(faceVerificationStatusProvider);
  }
}
