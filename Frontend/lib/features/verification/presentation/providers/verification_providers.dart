import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/repositories/verification_repository_impl.dart';
import '../../domain/models/verification_document.dart';
import '../../domain/repositories/verification_repository.dart';

/// Backend-backed verification repository, wired to the shared
/// authenticated [apiClientProvider] so every request carries the Firebase
/// ID token.
final verificationRepositoryProvider = Provider<VerificationRepository>(
  (ref) => VerificationRepositoryImpl(ref.watch(apiClientProvider)),
);

/// Per-type upload progress (0.0-1.0), for the in-flight submission only.
/// Cleared once a submit settles (success or failure) — this is presentation
/// state, not part of the verification record itself.
final verificationUploadProgressProvider =
    StateProvider<Map<VerificationDocumentType, double>>((ref) => const {});

/// The signed-in user's document verification statuses (income, asset,
/// aadhaar, NRI), keyed by type. Mirrors [myPhotosProvider]'s shape: an
/// [AsyncNotifier] wrapping the repository, with typed mutations that
/// optimistically update local state and republish whatever the backend
/// returns.
final verificationStatusesProvider = AsyncNotifierProvider<
    VerificationStatusesController,
    Map<VerificationDocumentType, VerificationDocumentRecord>>(
  VerificationStatusesController.new,
);

class VerificationStatusesController extends AsyncNotifier<
    Map<VerificationDocumentType, VerificationDocumentRecord>> {
  VerificationRepository get _repo => ref.read(verificationRepositoryProvider);

  @override
  Future<Map<VerificationDocumentType, VerificationDocumentRecord>>
      build() async {
    try {
      return await _repo.getStatuses();
    } catch (_) {
      // No statuses yet (backend route not live, or a genuinely fresh
      // user) — every type simply reads as "not submitted" rather than
      // surfacing a load error on first paint of the wizard step.
      return const {};
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue<Map<VerificationDocumentType, VerificationDocumentRecord>>.loading()
        .copyWithPrevious(state);
    state = await AsyncValue.guard(() => _repo.getStatuses());
  }

  /// Submits [file] as evidence for [type]. No-ops if a submission for the
  /// same type is already in flight, so a double-tap (or a slow first tap
  /// followed by an impatient second one) can't fire two uploads.
  Future<void> submit(VerificationDocumentType type, File file) async {
    final current = Map<VerificationDocumentType, VerificationDocumentRecord>.from(
      state.valueOrNull ?? const {},
    );
    if (current[type]?.isBusy ?? false) return;

    current[type] = VerificationDocumentRecord(
      type: type,
      status: VerificationSubmissionStatus.uploading,
    );
    state = AsyncValue.data(Map.unmodifiable(current));

    try {
      final record = await _repo.submitDocument(
        type: type,
        file: file,
        onProgress: (sent, total) {
          if (total <= 0) return;
          final progress = Map<VerificationDocumentType, double>.from(
            ref.read(verificationUploadProgressProvider),
          );
          progress[type] = sent / total;
          ref.read(verificationUploadProgressProvider.notifier).state =
              Map.unmodifiable(progress);
        },
      );
      final updated = Map<VerificationDocumentType, VerificationDocumentRecord>.from(
        state.valueOrNull ?? current,
      );
      updated[type] = record;
      state = AsyncValue.data(Map.unmodifiable(updated));
    } catch (_) {
      final failed = Map<VerificationDocumentType, VerificationDocumentRecord>.from(
        state.valueOrNull ?? current,
      );
      failed[type] = VerificationDocumentRecord(
        type: type,
        status: VerificationSubmissionStatus.failed,
      );
      state = AsyncValue.data(Map.unmodifiable(failed));
      rethrow;
    } finally {
      final progress = Map<VerificationDocumentType, double>.from(
        ref.read(verificationUploadProgressProvider),
      );
      progress.remove(type);
      ref.read(verificationUploadProgressProvider.notifier).state =
          Map.unmodifiable(progress);
    }
  }
}
