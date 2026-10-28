import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/mock_agent_referral_link_repository.dart';
import '../../domain/models/agent_referral_link.dart';
import '../../domain/repositories/agent_referral_link_repository.dart';
import '../../domain/services/whatsapp_share.dart';

/// `GET /agent/referral-links`. **Mock** — the endpoint is not built, and the
/// member app has no agent session to call it with (see
/// `ApiAgentReferralLinkRepository`). Override this to go live.
final agentReferralLinkRepositoryProvider =
    Provider<AgentReferralLinkRepository>(
      (ref) => const MockAgentReferralLinkRepository(),
    );

final agentReferralLinksProvider =
    FutureProvider.autoDispose<List<AgentReferralLink>>(
      (ref) =>
          ref.watch(agentReferralLinkRepositoryProvider).getReferralLinks(),
    );

/// How a share URL is opened; tests override it.
final urlOpenerProvider = Provider<UrlOpener>((ref) => openExternalUrl);
