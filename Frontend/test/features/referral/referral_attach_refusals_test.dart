import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/referral/domain/services/referral_attachment_controller.dart';

import 'referral_test_support.dart';

/// Attach refusals the agent contract lists (docs/agent-program/
/// FRONTEND_HANDOFF_DHATRI.md §5) that the first controller tests predate.
void main() {
  late InMemoryPendingReferralStore store;
  late FakeReferralRepository repository;

  ReferralAttachmentController controller() => ReferralAttachmentController(
    repository: repository,
    store: store,
    isSignedIn: () => true,
  );

  setUp(() {
    store = InMemoryPendingReferralStore(kPendingRavi);
    repository = FakeReferralRepository();
  });

  test('422 ALREADY_PAID is permanent: not retried, code cleared', () async {
    // "A code can only be added before your first plan." Sending it again on
    // every launch can never succeed.
    repository.onAttach = (_) =>
        throw ApiException(422, 'x', code: 'ALREADY_PAID');

    expect(
      await controller().attachPending(),
      ReferralAttachOutcome.notAllowed,
    );
    expect(store.value, isNull);

    // Nothing is waiting any more, so a later launch sends nothing.
    expect(
      await controller().attachPending(),
      ReferralAttachOutcome.nothingPending,
    );
    expect(repository.attached, hasLength(1));
  });

  test('422 PHONE_NOT_VERIFIED can pass later: kept and retried', () async {
    // Once the member verifies their phone the same code can attach, so it is
    // not dropped on the first refusal.
    repository.onAttach = (_) =>
        throw ApiException(422, 'x', code: 'PHONE_NOT_VERIFIED');

    expect(
      await controller().attachPending(),
      ReferralAttachOutcome.retryLater,
    );
    expect(store.value?.code, 'NM7K2P9X');
    expect(store.value?.attempts, 1);
  });
}
