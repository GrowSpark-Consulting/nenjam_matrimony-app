import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/repositories/support_repository_impl.dart';
import '../../domain/models/support_ticket.dart';
import '../../domain/repositories/support_repository.dart';

/// The live support repository, backed by the real `support` module. Swap back
/// to `SupportRepositoryUnavailable()` only if the backend is taken offline.
final supportRepositoryProvider = Provider<SupportRepository>(
  (ref) => SupportRepositoryImpl(ref.watch(apiClientProvider)),
);

/// The signed-in user's submitted support tickets, newest first.
final myTicketsProvider = FutureProvider.autoDispose<List<SupportTicket>>((ref) {
  return ref.watch(supportRepositoryProvider).getMyTickets();
});
