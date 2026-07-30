import '../../../../core/network/api_exception.dart';
import '../../../../l10n/app_localizations.dart';

/// Maps a thrown block/report error to a user-facing message. Shared by
/// `handleBlockUser` and `ReportUserSheet` so both flows describe the same
/// failure the same way instead of each inventing their own copy.
String safetyErrorMessage(AppLocalizations l10n, Object error) {
  if (error is ApiException) {
    switch (error.statusCode) {
      case null:
        return l10n.safetyErrorNetwork;
      case 401:
        return l10n.safetyErrorUnauthorized;
      case 400:
        return error.message.isNotEmpty
            ? error.message
            : l10n.safetyErrorValidation;
      case 404:
        return l10n.safetyErrorNotFound;
      case 409:
        return l10n.safetyErrorConflict;
      default:
        return l10n.safetyErrorGeneric;
    }
  }
  return l10n.safetyErrorGeneric;
}
