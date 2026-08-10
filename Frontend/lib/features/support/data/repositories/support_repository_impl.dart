import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/server_time.dart';
import '../../domain/models/support_ticket.dart';
import '../../domain/repositories/support_repository.dart';

/// Live backend implementation of [SupportRepository] — talks to the real
/// `support` module (`POST`/`GET /support/tickets`). Replaces
/// `SupportRepositoryUnavailable` once the endpoints exist; the providers and
/// UI are unchanged.
///
/// Wire mapping: the API field is `message` (the DB column is `body`), and the
/// `type`/`status` enums are lowerCamelCase strings matching this app's Dart
/// enum names, so mapping is a direct name lookup. Ticket history comes back in
/// a `{ items: [...] }` envelope (room for pagination later).
class SupportRepositoryImpl implements SupportRepository {
  SupportRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<SupportTicket> submitTicket({
    required SupportTicketType type,
    required String subject,
    required String message,
  }) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.supportTickets,
      data: {
        'type': _typeToWire(type),
        'subject': subject,
        'message': message,
      },
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    return _ticketFromJson(data);
  }

  @override
  Future<List<SupportTicket>> getMyTickets() async {
    final response = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.supportTickets,
    );
    final data = unwrapOrThrow(response.statusCode, response.data) ?? {};
    return (data['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(_ticketFromJson)
        .toList();
  }

  SupportTicket _ticketFromJson(Map<String, dynamic> json) => SupportTicket(
        id: json['id'] as String,
        type: _typeFromWire(json['type'] as String?),
        subject: json['subject'] as String? ?? '',
        message: json['message'] as String? ?? '',
        status: _statusFromWire(json['status'] as String?),
        createdAt: parseServerTime(json['createdAt'] as String),
      );

  String _typeToWire(SupportTicketType type) => switch (type) {
        SupportTicketType.contactSupport => 'contactSupport',
        SupportTicketType.bugReport => 'bugReport',
        SupportTicketType.featureRequest => 'featureRequest',
        SupportTicketType.appFeedback => 'appFeedback',
      };

  SupportTicketType _typeFromWire(String? wire) => switch (wire) {
        'bugReport' => SupportTicketType.bugReport,
        'featureRequest' => SupportTicketType.featureRequest,
        'appFeedback' => SupportTicketType.appFeedback,
        _ => SupportTicketType.contactSupport,
      };

  SupportTicketStatus _statusFromWire(String? wire) => switch (wire) {
        'inProgress' => SupportTicketStatus.inProgress,
        'resolved' => SupportTicketStatus.resolved,
        'closed' => SupportTicketStatus.closed,
        _ => SupportTicketStatus.open,
      };
}
