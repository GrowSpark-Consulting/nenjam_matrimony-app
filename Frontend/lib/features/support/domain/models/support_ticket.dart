/// What kind of support request this is — drives which copy the shared
/// ticket form shows, and lets a single intake endpoint (once one exists)
/// categorize submissions instead of needing four separate routes.
enum SupportTicketType { contactSupport, bugReport, featureRequest, appFeedback }

enum SupportTicketStatus { open, inProgress, resolved }

class SupportTicket {
  final String id;
  final SupportTicketType type;
  final String subject;
  final String message;
  final SupportTicketStatus status;
  final DateTime createdAt;

  const SupportTicket({
    required this.id,
    required this.type,
    required this.subject,
    required this.message,
    required this.status,
    required this.createdAt,
  });
}
