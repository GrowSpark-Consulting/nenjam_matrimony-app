import '../../domain/models/agent_referral_link.dart';
import '../../domain/repositories/agent_referral_link_repository.dart';

/// **MOCK** — `GET /agent/referral-links` is designed but not built. This
/// proves only that the app renders the contract's shape, not that any
/// backend returns it.
///
/// The share texts below are what the backend's `renderShareMessage` would
/// return for the approved templates (FRONTEND_HANDOFF_DHATRI.md §6) with
/// the contract's example agent (Ravi Kumar, `NM7K2P9X`) and a 5% discount,
/// while there is no web address: the `{link}` line is dropped. They are
/// mock *response data* — the app itself never fills a template.
class MockAgentReferralLinkRepository implements AgentReferralLinkRepository {
  const MockAgentReferralLinkRepository({this.shareable = true});

  /// False mimics a paused agent (every item `shareable: false`).
  final bool shareable;

  static const String mockEnglishMessage =
      "Hi! I'm Ravi Kumar. Join Nenjam, a trusted matrimony app, and use my "
      'referral code NM7K2P9X when you sign up to get 5% off your first plan.';

  static const String mockTamilMessage =
      'வணக்கம்! நான் Ravi Kumar. நம்பகமான திருமண வரன் தேடல் செயலியான '
      '"நெஞ்சம்" (Nenjam)-இல் இணையுங்கள். பதிவு செய்யும்போது என் பரிந்துரைக் '
      'குறியீடு NM7K2P9X பயன்படுத்தினால், உங்கள் முதல் திட்டத்தில் 5% '
      'தள்ளுபடி கிடைக்கும்.';

  @override
  Future<List<AgentReferralLink>> getReferralLinks() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return [
      AgentReferralLink.fromJson({
        'codeId': '3f1c2b9e-0d5a-4e7b-9c1a-2b6d8e4f7a10',
        'code': 'NM7K2P9X',
        'isPrimary': true,
        'link': null,
        'qrPayload': null,
        'shareMessages': [
          {
            'id': 'default',
            'text': {'en': mockEnglishMessage, 'ta': mockTamilMessage},
          },
        ],
        'shareable': shareable,
      }),
    ];
  }
}
