/// Member-side referral codes — the "Have a referral code?" box on the name
/// and date of birth step.
///
/// Shapes follow `docs/agent-program/agent-api.openapi.yaml`
/// (`POST /referrals/codes/validate`, `POST /registration/referral-code`).
/// The backend endpoints are designed but not built yet.
library;

/// NM + 6 characters, none of 0, O, 1, I, L — the contract's
/// `ReferralCodeInput` pattern after normalising, and the same rule as the
/// backend's `normalizeReferralCode`.
final RegExp _referralCodePattern = RegExp(r'^NM[2-9A-HJKMNP-Z]{6}$');

/// Turns what a member typed or pasted into a referral code, or null.
///
/// Trims, upper-cases, and removes spaces and hyphens, then accepts only a
/// well-formed code. Mirrors the backend's `normalizeReferralCode`, including
/// ASCII-only upper-casing, so a code this rejects is one the server would
/// call invalid anyway and is never sent.
String? normalizeReferralCode(String raw) {
  final cleaned = raw
      .trim()
      .replaceAllMapped(RegExp('[a-z]'), (m) => m.group(0)!.toUpperCase())
      .replaceAll(RegExp(r'[\s-]'), '');
  return _referralCodePattern.hasMatch(cleaned) ? cleaned : null;
}

/// `200` body of `POST /referrals/codes/validate`: only these two fields.
///
/// An unknown, inactive, malformed or not-active-agent code all come back
/// as the same `valid: false` — the server never says why, on purpose.
class ReferralCodeValidation {
  const ReferralCodeValidation({
    required this.valid,
    required this.agentDisplayName,
  });

  final bool valid;

  /// First name and last initial, e.g. "Ravi K.". Null when not [valid].
  final String? agentDisplayName;

  factory ReferralCodeValidation.fromJson(Map<String, dynamic> json) {
    final valid = json['valid'] == true;
    final name = json['agentDisplayName'];
    return ReferralCodeValidation(
      valid: valid,
      agentDisplayName: valid && name is String && name.isNotEmpty
          ? name
          : null,
    );
  }
}

/// `200` body of `POST /registration/referral-code`.
class ReferralAttachment {
  const ReferralAttachment({
    required this.attached,
    required this.agentDisplayName,
    required this.windowEndsAt,
  });

  final bool attached;
  final String? agentDisplayName;

  /// Last day the credit window covers (IST), `YYYY-MM-DD`, kept as the
  /// server's string — it is a calendar date, not an instant.
  final String? windowEndsAt;

  factory ReferralAttachment.fromJson(Map<String, dynamic> json) {
    final name = json['agentDisplayName'];
    final window = json['windowEndsAt'];
    return ReferralAttachment(
      attached: json['attached'] == true,
      agentDisplayName: name is String && name.isNotEmpty ? name : null,
      windowEndsAt: window is String && window.isNotEmpty ? window : null,
    );
  }
}

/// A validated code held on the device until it can be attached.
class PendingReferralCode {
  const PendingReferralCode({
    required this.code,
    required this.agentDisplayName,
    this.attempts = 0,
  });

  /// Already normalised (see [normalizeReferralCode]).
  final String code;
  final String? agentDisplayName;

  /// Attach attempts that ended in a retryable failure.
  final int attempts;

  PendingReferralCode withAttempt() => PendingReferralCode(
    code: code,
    agentDisplayName: agentDisplayName,
    attempts: attempts + 1,
  );

  Map<String, dynamic> toJson() => {
    'code': code,
    'agentDisplayName': agentDisplayName,
    'attempts': attempts,
  };

  /// Null for anything that is not a well-formed record — a corrupted value
  /// is treated as "no code", never as a crash or a guessed code.
  static PendingReferralCode? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final raw = json['code'];
    final code = raw is String ? normalizeReferralCode(raw) : null;
    if (code == null) return null;
    final name = json['agentDisplayName'];
    final attempts = json['attempts'];
    return PendingReferralCode(
      code: code,
      agentDisplayName: name is String && name.isNotEmpty ? name : null,
      attempts: attempts is int && attempts >= 0 ? attempts : 0,
    );
  }
}
