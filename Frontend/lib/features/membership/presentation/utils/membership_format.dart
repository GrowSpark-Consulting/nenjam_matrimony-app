import 'package:intl/intl.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/models/membership_models.dart';

/// Formats an integer paise amount as money: `399900` INR → `₹3,999`,
/// `399950` → `₹3,999.50`. Indian digit grouping for rupees. Any other
/// currency falls back to its ISO code.
String formatPaise(int paise, String currency) {
  final wholeRupees = paise % 100 == 0;
  final format = currency == 'INR'
      ? NumberFormat.currency(
          locale: 'en_IN',
          symbol: '₹',
          decimalDigits: wholeRupees ? 0 : 2,
        )
      : NumberFormat.currency(
          locale: 'en_IN',
          name: currency,
          decimalDigits: wholeRupees ? 0 : 2,
        );
  return format.format(paise / 100);
}

/// A calendar date in the member's language, e.g. "25 Jan 2027".
String formatMembershipDate(DateTime date, AppLocalizations l10n) =>
    DateFormat.yMMMd(l10n.localeName).format(date.toLocal());

/// One entitlement cell for [feature] on a plan, from the API's raw value.
/// Null when the plan doesn't list the feature or the value has an unknown
/// shape — the row is then left out rather than guessed.
String? describeEntitlement(
  MembershipFeature feature,
  Object? raw,
  AppLocalizations l10n,
) {
  final value = EntitlementValue.parse(raw);
  if (value == null) return null;
  if (value.included != null) {
    return value.included!
        ? l10n.membershipFeatureIncluded
        : l10n.membershipFeatureNotIncluded;
  }
  if (value.level != null) return value.level;
  if (value.unlimited) return l10n.membershipFeatureUnlimited;
  final limit = value.limit!;
  if (value.perMonths != null && value.perMonths! > 1) {
    return l10n.membershipFeatureEveryMonths(limit, value.perMonths!);
  }
  return switch (feature.period) {
    'MONTH' => l10n.membershipFeaturePerMonth(limit),
    'DAY' => l10n.membershipFeaturePerDay(limit),
    _ => '$limit',
  };
}

/// Localized label for a history item's `status` (and refund/revoke reason).
/// An unknown status is shown as the server sent it.
String describeHistoryStatus(
  MembershipHistoryItem item,
  AppLocalizations l10n,
) => switch (item.status) {
  'PENDING' => l10n.membershipStatusPending,
  'ACTIVE' => l10n.membershipStatusActive,
  'EXPIRED' => l10n.membershipStatusExpired,
  'CANCELLED' => switch (item.cancellationReason) {
    'REFUNDED' => l10n.membershipStatusRefunded,
    'REVOKED' => l10n.membershipStatusRevoked,
    _ => l10n.membershipStatusCancelled,
  },
  _ => item.status,
};
