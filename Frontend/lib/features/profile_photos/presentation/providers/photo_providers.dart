import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/repositories/photo_repository.dart';
import '../../domain/models/user_photo.dart';

/// Backend-backed photo repository, wired to the shared authenticated
/// [apiClientProvider] so every request carries the Firebase ID token.
final photoRepositoryProvider = Provider<PhotoRepository>(
  (ref) => PhotoRepository(ref.watch(apiClientProvider)),
);

/// The signed-in user's photos (0-6), newest ordering from the backend, each
/// with a fresh presigned URL. Read-only consumers (profile dashboard, review
/// screen) watch this; mutations go through [PhotosController], which keeps
/// this provider's cache in sync.
final myPhotosProvider = AsyncNotifierProvider<PhotosController, List<UserPhoto>>(
  PhotosController.new,
);

/// Owns photo state and every mutation. Each mutation optimistically flips the
/// provider into a loading state, calls the backend, and republishes the
/// authoritative list the backend returns — so the UI (wizard step, profile
/// dashboard, edit profile) refreshes immediately and identically everywhere
/// this provider is watched.
class PhotosController extends AsyncNotifier<List<UserPhoto>> {
  PhotoRepository get _repo => ref.read(photoRepositoryProvider);

  @override
  Future<List<UserPhoto>> build() => _repo.fetchPhotos();

  /// Re-fetches from the backend (e.g. pull-to-refresh or retry after error).
  Future<void> refresh() async {
    state = const AsyncValue<List<UserPhoto>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(_repo.fetchPhotos);
  }

  Future<void> upload(File file, {bool? isPrimary}) async {
    state = const AsyncValue<List<UserPhoto>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      await _repo.upload(file, isPrimary: isPrimary);
      return _repo.fetchPhotos();
    });
  }

  Future<void> replace(String id, File file) async {
    state = const AsyncValue<List<UserPhoto>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      await _repo.replace(id, file);
      return _repo.fetchPhotos();
    });
  }

  Future<void> delete(String id) async {
    state = const AsyncValue<List<UserPhoto>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(() => _repo.delete(id));
  }

  Future<void> reorder(List<String> orderedIds) async {
    state = const AsyncValue<List<UserPhoto>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(() => _repo.reorder(orderedIds));
  }

  Future<void> setPrimary(String id) async {
    state = const AsyncValue<List<UserPhoto>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(() => _repo.setPrimary(id));
  }
}
