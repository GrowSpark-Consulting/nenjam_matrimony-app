import 'link_referral_store.dart';

LinkReferralStore platformLinkReferralStore() => _shared;

final MemoryLinkReferralStore _shared = MemoryLinkReferralStore();
