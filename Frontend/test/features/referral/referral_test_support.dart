import 'dart:async';

import 'package:nenjam_matrimony/features/referral/data/services/pending_referral_store.dart';
import 'package:nenjam_matrimony/features/referral/domain/models/referral_models.dart';
import 'package:nenjam_matrimony/features/referral/domain/repositories/referral_repository.dart';

/// Holds the pending code in memory, so a "restart" is a new controller over
/// the same store.
class InMemoryPendingReferralStore implements PendingReferralStore {
  InMemoryPendingReferralStore([this.value]);

  PendingReferralCode? value;

  @override
  PendingReferralCode? read() => value;

  @override
  Future<void> write(PendingReferralCode code) async => value = code;

  @override
  Future<void> clear() async => value = null;
}

/// Records every call; answers come from [onValidate] / [onAttach].
class FakeReferralRepository implements ReferralRepository {
  FakeReferralRepository({this.onValidate, this.onAttach});

  FutureOr<ReferralCodeValidation> Function(String code)? onValidate;
  FutureOr<ReferralAttachment> Function(String code)? onAttach;

  final List<String> validated = [];
  final List<String> attached = [];

  @override
  Future<ReferralCodeValidation> validateCode(String code) async {
    validated.add(code);
    return onValidate?.call(code) ??
        const ReferralCodeValidation(valid: false, agentDisplayName: null);
  }

  @override
  Future<ReferralAttachment> attachCode(String code) async {
    attached.add(code);
    return onAttach?.call(code) ??
        const ReferralAttachment(
          attached: true,
          agentDisplayName: 'Ravi K.',
          windowEndsAt: '2026-12-27',
        );
  }
}

const PendingReferralCode kPendingRavi = PendingReferralCode(
  code: 'NM7K2P9X',
  agentDisplayName: 'Ravi K.',
);
