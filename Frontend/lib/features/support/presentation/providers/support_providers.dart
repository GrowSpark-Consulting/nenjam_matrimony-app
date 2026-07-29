import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/support_repository_unavailable.dart';
import '../../domain/models/support_ticket.dart';
import '../../domain/repositories/support_repository.dart';

final supportRepositoryProvider = Provider<SupportRepository>(
  (ref) => const SupportRepositoryUnavailable(),
);

/// The signed-in user's submitted support tickets. Always resolves to an
/// [AsyncError] today, by design, until a real backend implementation is
/// wired in — see [SupportRepositoryUnavailable].
final myTicketsProvider = FutureProvider.autoDispose<List<SupportTicket>>((ref) {
  return ref.watch(supportRepositoryProvider).getMyTickets();
});
