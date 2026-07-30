/// Mirrors the backend's `ReportReason` enum
/// (backend/libs/database/prisma/schema.prisma) — [wireValue] is the exact
/// string the API expects in `POST /users/:id/report`'s body.
enum ReportReason {
  fakeProfile,
  inappropriateContent,
  harassment,
  spam,
  other;

  String get wireValue => switch (this) {
        ReportReason.fakeProfile => 'FAKE_PROFILE',
        ReportReason.inappropriateContent => 'INAPPROPRIATE_CONTENT',
        ReportReason.harassment => 'HARASSMENT',
        ReportReason.spam => 'SPAM',
        ReportReason.other => 'OTHER',
      };
}
