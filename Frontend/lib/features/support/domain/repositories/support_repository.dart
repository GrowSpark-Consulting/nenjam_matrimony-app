import 'package:dio/dio.dart' show CancelToken;
import '../models/support_ticket.dart';

/// Pure abstract contract for the Support Center (Contact Support / Report a
/// Bug / Feature Request / App Feedback / Ticket History).
///
/// No backend endpoint exists for any of this yet — the `support` module on
/// the backend has no controller at all. Deliberately no concrete
/// implementation guesses at a URL and issues a real network call against
/// it; see [SupportRepositoryUnavailable] for what's wired today. A backend
/// engineer can implement this interface for real once the module ships,
/// with zero changes to the providers or UI.
abstract interface class SupportRepository {
  Future<SupportTicket> submitTicket({
    required SupportTicketType type,
    required String subject,
    required String message,
  });

  Future<List<SupportTicket>> getMyTickets({CancelToken? cancelToken});
}
