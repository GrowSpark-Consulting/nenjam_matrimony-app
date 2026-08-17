import 'package:dio/dio.dart' show CancelToken;
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
  final cancelToken = CancelToken();
  // Cancels the in-flight request when this provider is disposed — i.e. the
  // moment the screen that asked for it is popped. Without this the response
  // still arrives and is still parsed, only to be discarded, which on a slow
  // connection also keeps competing for bandwidth with whatever the user
  // navigated to instead.
  ref.onDispose(cancelToken.cancel);
  return ref
      .watch(supportRepositoryProvider)
      .getMyTickets(cancelToken: cancelToken);
});
