import '../models/agent_referral_link.dart';

/// `GET /agent/referral-links` — an agent endpoint (the agent's own access
/// token, not Firebase). Not paginated: an agent holds a handful of codes.
abstract class AgentReferralLinkRepository {
  Future<List<AgentReferralLink>> getReferralLinks();
}
