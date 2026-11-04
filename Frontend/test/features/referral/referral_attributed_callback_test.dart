import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/referral/domain/services/referral_attachment_controller.dart';

import 'referral_test_support.dart';

/// `onAttributed` is what makes a code/link referral exempt from the selfie
/// step, so it must fire only when the backend confirmed an attribution.
void main() {
  late InMemoryPendingReferralStore store;
  late FakeReferralRepository repository;
  var attributed = 0;

  ReferralAttachmentController controller() => ReferralAttachmentController(
    repository: repository,
    store: store,
    isSignedIn: () => true,
    onAttributed: () => attributed++,
  );

  setUp(() {
    store = InMemoryPendingReferralStore(kPendingRavi);
    repository = FakeReferralRepository();
    attributed = 0;
  });

  test('200 attached → attributed', () async {
    expect(await controller().attachPending(), ReferralAttachOutcome.attached);
    expect(attributed, 1);
  });

  test('409 ALREADY_ATTRIBUTED → attributed (an agent already holds them)',
      () async {
    repository.onAttach = (_) =>
        throw ApiException(409, 'x', code: 'ALREADY_ATTRIBUTED');
    expect(
      await controller().attachPending(),
      ReferralAttachOutcome.alreadyAttributed,
    );
    expect(attributed, 1);
  });

  for (final entry in {
    'CODE_NOT_FOUND': 404,
    'SELF_REFERRAL': 422,
    'ALREADY_PAID': 422,
  }.entries) {
    test('${entry.key} → not attributed', () async {
      repository.onAttach = (_) =>
          throw ApiException(entry.value, 'x', code: entry.key);
      await controller().attachPending();
      expect(attributed, 0);
    });
  }

  test('retryable failure and nothing pending → not attributed', () async {
    repository.onAttach = (_) => throw ApiException(503, 'x');
    expect(await controller().attachPending(), ReferralAttachOutcome.retryLater);
    store.value = null;
    await controller().attachPending();
    expect(attributed, 0);
  });
}
