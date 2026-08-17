import 'package:dio/dio.dart' show CancelToken;
import '../../domain/models/support_ticket.dart';
import '../../domain/repositories/support_repository.dart';

/// TODO(backend): swap this for a real Dio-backed implementation once the
/// `support` module ships (today it has no controller at all). Throws
/// immediately rather than guessing at a URL and making a real network call
/// against a contract nobody has defined yet — the providers surface this
/// as a normal [AsyncError], so ticket submission and history both show an
/// honest "not available yet" + retry state, never a fake success.
class SupportRepositoryUnavailable implements SupportRepository {
  const SupportRepositoryUnavailable();

  @override
  Future<SupportTicket> submitTicket({
    required SupportTicketType type,
    required String subject,
    required String message,
  }) {
    throw StateError('Support tickets are not available yet.');
  }

  @override
  Future<List<SupportTicket>> getMyTickets({CancelToken? cancelToken}) {
    throw StateError('Support ticket history is not available yet.');
  }
}
