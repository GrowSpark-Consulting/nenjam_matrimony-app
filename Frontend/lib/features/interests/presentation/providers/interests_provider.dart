import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../data/repositories/mock_interests_repository.dart';
import '../../domain/repositories/interests_repository.dart';

/// [InterestsRepository]/[InterestRecord] and the real
/// `InterestsRepositoryImpl` already existed — this file is the missing
/// piece: nothing wired them to a provider before, since the backend
/// `interests` controller those endpoints target is still an empty stub.
/// Swap [MockInterestsRepository] for `InterestsRepositoryImpl` (already
/// implemented, just dormant) once that controller ships.
final interestsRepositoryProvider = Provider<InterestsRepository>(
  (ref) => MockInterestsRepository(),
);

/// Both lists together — sent and received interests are two views over
/// the same underlying relationship data, and several actions (accept,
/// decline) only make sense with both in hand, so one notifier owns both
/// rather than two independent ones that could drift apart.
class InterestsState {
  const InterestsState({required this.sent, required this.received});

  final List<InterestRecord> sent;
  final List<InterestRecord> received;

  InterestsState copyWith({List<InterestRecord>? sent, List<InterestRecord>? received}) =>
      InterestsState(sent: sent ?? this.sent, received: received ?? this.received);
}

/// Single source of truth for every Interest action across the app —
/// Discover, Matches, Profile Detail, the Sent/Received screens, and the
/// Inbox's interests tabs all read from and mutate through this one
/// notifier, so no screen can disagree with another about relationship
/// state. Optimistic updates are applied synchronously (before the
/// `await`), so a rapid second tap sees the already-updated state and the
/// per-action guards below prevent it from firing twice.
class InterestsNotifier extends AsyncNotifier<InterestsState> {
  @override
  Future<InterestsState> build() async {
    final repo = ref.watch(interestsRepositoryProvider);
    final results = await Future.wait([repo.getSent(), repo.getReceived()]);
    return InterestsState(sent: results[0], received: results[1]);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(interestsRepositoryProvider);
      final results = await Future.wait([repo.getSent(), repo.getReceived()]);
      return InterestsState(sent: results[0], received: results[1]);
    });
  }

  /// Sends an interest to [profile]. No-ops if the relationship is already
  /// anything other than [InterestRelationshipStatus.none]/[declined] —
  /// this is what makes rapid repeated taps and multiple call sites (a
  /// Discover card, then the same profile's Matches card, then its Profile
  /// Detail page) all collapse into at most one real send.
  Future<void> sendInterest(DiscoveryProfileEntity profile) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final existing = deriveRelationshipStatus(
      profileId: profile.id,
      sent: current.sent,
      received: current.received,
    );
    if (existing != InterestRelationshipStatus.none &&
        existing != InterestRelationshipStatus.declined) {
      return;
    }

    final optimisticId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = InterestRecord(
      id: optimisticId,
      profile: profile,
      sentAt: DateTime.now(),
      status: InterestStatus.pending,
    );
    state = AsyncValue.data(current.copyWith(sent: [optimistic, ...current.sent]));

    try {
      final saved = await ref.read(interestsRepositoryProvider).sendInterest(profile);
      final latest = state.valueOrNull;
      if (latest == null) return;
      state = AsyncValue.data(latest.copyWith(sent: [
        for (final r in latest.sent) if (r.id == optimisticId) saved else r,
      ]));
    } catch (_) {
      // Rollback — remove the optimistic record so the button reverts to
      // "Send Interest" rather than getting stuck showing "Sent".
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data(latest.copyWith(
          sent: latest.sent.where((r) => r.id != optimisticId).toList(),
        ));
      }
      rethrow;
    }
  }

  /// Accepts or declines a pending *received* interest. No-ops if it's
  /// already been responded to, preventing a duplicate response from a
  /// rapid double-tap.
  Future<void> respond(String interestId, {required bool accept}) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final alreadyResponded = current.received.any(
      (r) => r.id == interestId && r.status != InterestStatus.pending,
    );
    if (alreadyResponded) return;

    final newStatus = accept ? InterestStatus.accepted : InterestStatus.declined;
    state = AsyncValue.data(current.copyWith(received: [
      for (final r in current.received)
        if (r.id == interestId) r.copyWith(status: newStatus) else r,
    ]));

    try {
      await ref.read(interestsRepositoryProvider).respond(interestId, accept: accept);
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data(latest.copyWith(received: [
          for (final r in latest.received)
            if (r.id == interestId) r.copyWith(status: InterestStatus.pending) else r,
        ]));
      }
      rethrow;
    }
  }

  /// Withdraws a pending *sent* interest. Only valid while pending — there
  /// is no unmatch/remove-connection concept for an already-accepted one.
  Future<void> withdraw(String interestId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final target = current.sent.where((r) => r.id == interestId);
    if (target.isEmpty || target.first.status != InterestStatus.pending) return;
    final removed = target.first;

    state = AsyncValue.data(current.copyWith(
      sent: current.sent.where((r) => r.id != interestId).toList(),
    ));

    try {
      await ref.read(interestsRepositoryProvider).withdraw(interestId);
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) {
        state = AsyncValue.data(latest.copyWith(sent: [removed, ...latest.sent]));
      }
      rethrow;
    }
  }
}

final interestsNotifierProvider = AsyncNotifierProvider<InterestsNotifier, InterestsState>(
  InterestsNotifier.new,
);

/// Drives the Inbox's "Interests Received" tab (and the standalone
/// `InterestsReceivedPage`). Kept as the same name/type it always was so no
/// existing watch call site needs to change — now derived from
/// [interestsNotifierProvider] instead of fetching independently.
final receivedInterestsProvider = Provider<AsyncValue<List<InterestRecord>>>(
  (ref) => ref.watch(interestsNotifierProvider).whenData((s) => s.received),
);

/// Drives the Inbox's "Interests Sent" tab (and the standalone
/// `InterestsSentPage`).
final sentInterestsProvider = Provider<AsyncValue<List<InterestRecord>>>(
  (ref) => ref.watch(interestsNotifierProvider).whenData((s) => s.sent),
);

/// What is the current user's relationship with this profile? The single
/// read every "Send Interest" button across the app watches.
final interestRelationshipStatusProvider =
    Provider.family<InterestRelationshipStatus, String>((ref, profileId) {
  final state = ref.watch(interestsNotifierProvider).valueOrNull;
  if (state == null) return InterestRelationshipStatus.none;
  return deriveRelationshipStatus(
    profileId: profileId,
    sent: state.sent,
    received: state.received,
  );
});
