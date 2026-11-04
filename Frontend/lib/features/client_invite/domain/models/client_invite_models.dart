/// `POST /client-invites/otp/request` 200.
class ClientOtpChallenge {
  const ClientOtpChallenge({
    required this.expiresInSeconds,
    required this.resendAfterSeconds,
  });

  final int expiresInSeconds;
  final int resendAfterSeconds;

  factory ClientOtpChallenge.fromJson(Map<String, dynamic> json) {
    int whole(Object? v, int fallback) =>
        v is num && v >= 0 ? v.toInt() : fallback;
    return ClientOtpChallenge(
      expiresInSeconds: whole(json['expiresInSeconds'], 300),
      resendAfterSeconds: whole(json['resendAfterSeconds'], 30),
    );
  }
}

/// The CLIENT-scoped access token from `POST /client-invites/otp/verify`.
///
/// Memory only: it is never written to disk and [toString] never prints it,
/// so it cannot reach a log through string interpolation.
class ClientAccessToken {
  const ClientAccessToken(this.value);

  final String value;

  /// Null for anything that is not a CLIENT session with a token.
  static ClientAccessToken? tryFromJson(Map<String, dynamic> json) {
    final token = json['accessToken'];
    if (token is! String || token.isEmpty) return null;
    if (json['scope'] != 'CLIENT') return null;
    return ClientAccessToken(token);
  }

  @override
  String toString() => 'ClientAccessToken(<redacted>)';
}

/// One answered question of an invitation, shown read-only.
class InviteDetailRow {
  const InviteDetailRow(this.label, this.value);
  final String label;
  final String value;
}

/// One profile section the agent filled (e.g. `religionDetails`).
class InviteDetailSection {
  const InviteDetailSection(this.key, this.rows);
  final String key;
  final List<InviteDetailRow> rows;
}

/// An invitation as the client sees it (`ClientInvite`).
class ClientInvite {
  const ClientInvite({
    required this.id,
    required this.agentDisplayName,
    required this.expiresOn,
    required this.discountPercent,
    required this.sections,
  });

  final String id;
  final String agentDisplayName;

  /// `YYYY-MM-DD`, an Indian calendar date: shown as received.
  final String expiresOn;
  final int? discountPercent;
  final List<InviteDetailSection> sections;

  /// Null for an item without an id or agent name (it cannot be acted on).
  static ClientInvite? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final agent = json['agentDisplayName'];
    if (id is! String || id.isEmpty || agent is! String || agent.isEmpty) {
      return null;
    }
    final expires = json['expiresOn'];
    final pct = json['referredMemberDiscountPercent'];
    return ClientInvite(
      id: id,
      agentDisplayName: agent,
      expiresOn: expires is String ? expires : '',
      discountPercent: pct is num ? pct.toInt() : null,
      sections: _sections(json['details']),
    );
  }

  /// Sections in the order received, partner preferences last. A `fooCode`
  /// entry is skipped when the server also sent its label (`foo`): the
  /// client sees "Hindu", not "HINDU".
  static List<InviteDetailSection> _sections(Object? details) {
    if (details is! Map) return const [];
    final out = <InviteDetailSection>[];
    InviteDetailSection? partner;
    details.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final rows = <InviteDetailRow>[];
      _flatten(value, '', rows);
      if (rows.isEmpty) return;
      final section = InviteDetailSection(key, rows);
      if (key == 'partnerPreference') {
        partner = section;
      } else {
        out.add(section);
      }
    });
    final p = partner;
    if (p != null) out.add(p);
    return out;
  }

  static void _flatten(
    Map<dynamic, dynamic> map,
    String prefix,
    List<InviteDetailRow> rows,
  ) {
    map.forEach((k, v) {
      if (k is! String || v == null) return;
      if (k.endsWith('Code') && map.containsKey(k.substring(0, k.length - 4))) {
        return;
      }
      final name = prefix.isEmpty ? k : '$prefix.$k';
      if (v is Map) {
        _flatten(v, name, rows);
      } else if (v is List) {
        for (final item in v) {
          if (item is Map) {
            _flatten(item, name, rows);
          } else if (item != null && '$item'.trim().isNotEmpty) {
            rows.add(InviteDetailRow(name, '$item'));
          }
        }
      } else if ('$v'.trim().isNotEmpty) {
        rows.add(InviteDetailRow(name, '$v'));
      }
    });
  }
}

/// `POST /client-invites/{id}/accept` 200 (`ClientAcceptResult`).
class ClientAcceptResult {
  const ClientAcceptResult({
    required this.firebaseCustomToken,
    required this.agentDisplayName,
    required this.windowEndsAt,
    this.profileReady,
  });

  /// `profileReady` from the response, exactly as sent. True: her member
  /// profile exists. False: it could not be made yet (accept again once).
  /// Null: the field was missing or not a boolean; treated as not ready.
  final bool? profileReady;

  /// Null/empty means "no token to exchange" (the guide says this may happen
  /// once real SMS arrives, when she already holds a Firebase session).
  final String? firebaseCustomToken;
  final String? agentDisplayName;
  final String? windowEndsAt;

  factory ClientAcceptResult.fromJson(Map<String, dynamic> json) {
    final t = json['firebaseCustomToken'];
    final a = json['agentDisplayName'];
    final w = json['windowEndsAt'];
    final ready = json['profileReady'];
    return ClientAcceptResult(
      firebaseCustomToken: t is String && t.isNotEmpty ? t : null,
      agentDisplayName: a is String ? a : null,
      windowEndsAt: w is String ? w : null,
      profileReady: ready is bool ? ready : null,
    );
  }

  @override
  String toString() => 'ClientAcceptResult(<redacted>)';
}
