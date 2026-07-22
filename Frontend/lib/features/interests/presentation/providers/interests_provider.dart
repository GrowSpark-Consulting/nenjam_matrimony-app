import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Drives the Inbox's "Interests Received" tab (and the standalone
/// `InterestsReceivedPage`).
final receivedInterestsProvider = FutureProvider<List<InterestRecord>>(
  (ref) => ref.watch(interestsRepositoryProvider).getReceived(),
);

/// Drives the Inbox's "Interests Sent" tab (and the standalone
/// `InterestsSentPage`).
final sentInterestsProvider = FutureProvider<List<InterestRecord>>(
  (ref) => ref.watch(interestsRepositoryProvider).getSent(),
);
