import '../../../../l10n/app_localizations.dart';
import '../../domain/repositories/interests_repository.dart';

/// Shared "Pending"/"Accepted"/"Declined" label for an [InterestStatus] —
/// used by the Inbox interests tabs and the standalone Sent/Received
/// screens so the wording can never drift between the two surfaces.
String interestStatusLabel(InterestStatus status, AppLocalizations l10n) {
  switch (status) {
    case InterestStatus.pending:
      return l10n.interestStatusPending;
    case InterestStatus.accepted:
      return l10n.interestStatusAccepted;
    case InterestStatus.declined:
      return l10n.interestStatusDeclined;
  }
}
