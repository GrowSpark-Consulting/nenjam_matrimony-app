/// Shapes from `docs/agent-program/agent-api.openapi.yaml`
/// (`ReferralLink`, `LocalizedText`). Hand-written, parse-tolerant: a field
/// that is missing or the wrong type becomes null / empty, never a guess.
library;

/// `{ en, ta }`.
class LocalizedText {
  const LocalizedText({required this.en, required this.ta});

  final String en;
  final String ta;

  factory LocalizedText.fromJson(Object? json) {
    final map = json is Map ? json : const <String, dynamic>{};
    final en = map['en'];
    final ta = map['ta'];
    return LocalizedText(
      en: en is String ? en : '',
      ta: ta is String ? ta : '',
    );
  }

  /// The text for [languageCode] (`ta` or anything else → `en`), or null
  /// when that language's text is empty. Never falls back to the other
  /// language silently — the caller decides what a missing message means.
  String? forLanguage(String languageCode) {
    final text = (languageCode == 'ta' ? ta : en).trim();
    return text.isEmpty ? null : text;
  }
}

/// One entry of `ReferralLink.shareMessages`: the finished text, with the
/// code (and the link, when there is one) already filled in by the backend.
class AgentShareMessage {
  const AgentShareMessage({required this.id, required this.text});

  final String id;
  final LocalizedText text;

  factory AgentShareMessage.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    return AgentShareMessage(
      id: id is String ? id : '',
      text: LocalizedText.fromJson(json['text']),
    );
  }
}

/// One item of `GET /agent/referral-links`.
class AgentReferralLink {
  const AgentReferralLink({
    required this.codeId,
    required this.code,
    required this.isPrimary,
    required this.link,
    required this.qrPayload,
    required this.shareMessages,
    required this.shareable,
  });

  final String codeId;
  final String code;
  final bool isPrimary;

  /// Null until the public web address is decided.
  final String? link;

  /// Null whenever [link] is null.
  final String? qrPayload;

  final List<AgentShareMessage> shareMessages;

  /// False while the agent is paused.
  final bool shareable;

  factory AgentReferralLink.fromJson(Map<String, dynamic> json) {
    String? nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;
    final messages = json['shareMessages'];
    return AgentReferralLink(
      codeId: nonEmpty(json['codeId']) ?? '',
      code: nonEmpty(json['code']) ?? '',
      isPrimary: json['isPrimary'] == true,
      link: nonEmpty(json['link']),
      qrPayload: nonEmpty(json['qrPayload']),
      shareMessages: [
        if (messages is List)
          for (final m in messages)
            if (m is Map)
              AgentShareMessage.fromJson(Map<String, dynamic>.from(m)),
      ],
      // Absent means "not confirmed shareable" — fail closed.
      shareable: json['shareable'] == true,
    );
  }

  /// The ready-made text for [languageCode] — the first of this link's own
  /// messages that has text in that language, exactly as returned — or null
  /// when there is none.
  String? shareTextFor(String languageCode) {
    for (final message in shareMessages) {
      final text = message.text.forLanguage(languageCode);
      if (text != null) return text;
    }
    return null;
  }
}
