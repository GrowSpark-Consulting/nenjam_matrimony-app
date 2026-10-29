import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/network/api_exception.dart';
import 'package:nenjam_matrimony/features/referral/domain/models/referral_models.dart';
import 'package:nenjam_matrimony/features/referral/domain/services/referral_attachment_controller.dart';

import 'referral_test_support.dart';

/// The attach step: once, only signed in, and never a reason signup fails.
/// Every repository here is a fake — nothing in this file proves the real
/// backend behaves this way (its endpoints are not built yet).
void main() {
  late InMemoryPendingReferralStore store;
  late FakeReferralRepository repository;
  var signedIn = false;

  ReferralAttachmentController controller() => ReferralAttachmentController(
    repository: repository,
    store: store,
    isSignedIn: () => signedIn,
  );

  setUp(() {
    store = InMemoryPendingReferralStore();
    repository = FakeReferralRepository();
    signedIn = false;
  });

  test('no code entered: nothing is sent', () async {
    signedIn = true;
    expect(
      await controller().attachPending(),
      ReferralAttachOutcome.nothingPending,
    );
    expect(repository.attached, isEmpty);
  });

  test('not signed in yet: the code is kept and nothing is sent', () async {
    store.value = kPendingRavi;
    expect(
      await controller().attachPending(),
      ReferralAttachOutcome.notSignedIn,
    );
    expect(repository.attached, isEmpty);
    expect(store.value, isNotNull);
  });

  test('success clears the code, so it is never sent twice', () async {
    store.value = kPendingRavi;
    signedIn = true;
    final c = controller();
    expect(await c.attachPending(), ReferralAttachOutcome.attached);
    expect(repository.attached, ['NM7K2P9X']);
    expect(store.value, isNull);

    expect(await c.attachPending(), ReferralAttachOutcome.nothingPending);
    expect(repository.attached, hasLength(1));
  });

  test('concurrent triggers share one request', () async {
    store.value = kPendingRavi;
    signedIn = true;
    final gate = Completer<ReferralAttachment>();
    repository.onAttach = (_) => gate.future;
    final c = controller();

    final first = c.attachPending();
    final second = c.attachPending();
    gate.complete(
      const ReferralAttachment(
        attached: true,
        agentDisplayName: 'Ravi K.',
        windowEndsAt: '2026-12-27',
      ),
    );
    expect(await first, ReferralAttachOutcome.attached);
    expect(await second, ReferralAttachOutcome.attached);
    expect(repository.attached, hasLength(1));
  });

  group('contract refusals are final and clear the code', () {
    final cases = {
      ApiException(409, 'x', code: 'ALREADY_ATTRIBUTED'):
          ReferralAttachOutcome.alreadyAttributed,
      ApiException(404, 'x', code: 'CODE_NOT_FOUND'):
          ReferralAttachOutcome.codeNotFound,
      ApiException(422, 'x', code: 'SELF_REFERRAL'):
          ReferralAttachOutcome.notAllowed,
      ApiException(400, 'x', code: 'VALIDATION_FAILED'):
          ReferralAttachOutcome.codeNotFound,
    };
    for (final entry in cases.entries) {
      test('${entry.key.statusCode} ${entry.key.code}', () async {
        store.value = kPendingRavi;
        signedIn = true;
        repository.onAttach = (_) => throw entry.key;
        expect(await controller().attachPending(), entry.value);
        expect(store.value, isNull);
      });
    }
  });

  group('retryable failures keep the code, up to the cap', () {
    final cases = <String, Object>{
      'network': Exception('socket closed'),
      '429': ApiException(429, 'x', code: 'RATE_LIMITED'),
      '401': ApiException(401, 'x', code: 'UNAUTHORIZED'),
      // Attach error codes beyond the contract's are still pending; an
      // unknown one is retried, never guessed at.
      'unlisted 422': ApiException(422, 'x', code: 'SOMETHING_NEW'),
    };
    for (final entry in cases.entries) {
      test(entry.key, () async {
        store.value = kPendingRavi;
        signedIn = true;
        repository.onAttach = (_) => throw entry.value;
        expect(
          await controller().attachPending(),
          ReferralAttachOutcome.retryLater,
        );
        expect(store.value?.code, 'NM7K2P9X');
        expect(store.value?.attempts, 1);
      });
    }

    test('gives up after maxAttempts and clears', () async {
      store.value = kPendingRavi;
      signedIn = true;
      repository.onAttach = (_) => throw Exception('offline');
      final c = controller();
      for (var i = 1; i < ReferralAttachmentController.maxAttempts; i++) {
        expect(await c.attachPending(), ReferralAttachOutcome.retryLater);
      }
      expect(await c.attachPending(), ReferralAttachOutcome.gaveUp);
      expect(store.value, isNull);
      expect(
        repository.attached,
        hasLength(ReferralAttachmentController.maxAttempts),
      );
    });
  });

  test('a 200 with attached: false is not success — kept, counted', () async {
    store.value = kPendingRavi;
    signedIn = true;
    repository.onAttach = (_) => const ReferralAttachment(
      attached: false,
      agentDisplayName: null,
      windowEndsAt: null,
    );
    expect(
      await controller().attachPending(),
      ReferralAttachOutcome.retryLater,
    );
    expect(store.value?.attempts, 1);
  });

  test('disabled (feature off): sends nothing and leaves the code', () async {
    store.value = kPendingRavi;
    signedIn = true;
    final c = ReferralAttachmentController(
      repository: repository,
      store: store,
      isSignedIn: () => true,
      isEnabled: () => false,
    );
    expect(await c.attachPending(), ReferralAttachOutcome.nothingPending);
    expect(repository.attached, isEmpty);
    expect(store.value, isNotNull);
  });

  test('the attempt count survives a restart, so retries stay capped', () async {
    store.value = kPendingRavi;
    signedIn = true;
    repository.onAttach = (_) => throw Exception('offline');
    // Each "process" is a fresh controller over the same persisted store.
    for (var i = 1; i < ReferralAttachmentController.maxAttempts; i++) {
      expect(
        await controller().attachPending(),
        ReferralAttachOutcome.retryLater,
      );
    }
    expect(await controller().attachPending(), ReferralAttachOutcome.gaveUp);
    expect(
      await controller().attachPending(),
      ReferralAttachOutcome.nothingPending,
    );
    expect(
      repository.attached,
      hasLength(ReferralAttachmentController.maxAttempts),
    );
  });

  test('a 404 with no contract code (endpoint not deployed) is retried, '
      'not mistaken for CODE_NOT_FOUND', () async {
    store.value = kPendingRavi;
    signedIn = true;
    repository.onAttach = (_) => throw ApiException(404, 'Cannot POST');
    expect(
      await controller().attachPending(),
      ReferralAttachOutcome.retryLater,
    );
    expect(store.value, isNotNull);
  });

  test('5xx is retried', () async {
    store.value = kPendingRavi;
    signedIn = true;
    repository.onAttach = (_) => throw ApiException(503, 'down');
    expect(
      await controller().attachPending(),
      ReferralAttachOutcome.retryLater,
    );
  });

  test('a failing store never throws out of the controller', () async {
    signedIn = true;
    final c = ReferralAttachmentController(
      repository: repository,
      store: _ThrowingStore(),
      isSignedIn: () => true,
    );
    expect(await c.attachPending(), ReferralAttachOutcome.retryLater);
  });

  // ─── Signup paths ──────────────────────────────────────────────────

  test('phone OTP signup: code waits through signup, attaches once after the '
      'verify step signs the member in', () async {
    // Name step: no session yet, the code validated and was stored.
    store.value = kPendingRavi;
    final c = controller();
    // Remaining steps run without a session; nothing is attached.
    expect(await c.attachPending(), ReferralAttachOutcome.notSignedIn);
    // Verify Mobile mints the session, saves and finalizes, then attaches.
    signedIn = true;
    expect(await c.attachPending(), ReferralAttachOutcome.attached);
    expect(repository.attached, ['NM7K2P9X']);
  });

  test('email signup: same as phone — the session is minted on Verify '
      'Mobile, and only then is the code attached', () async {
    store.value = kPendingRavi;
    final c = controller();
    expect(await c.attachPending(), ReferralAttachOutcome.notSignedIn);
    expect(repository.attached, isEmpty);
    signedIn = true;
    expect(await c.attachPending(), ReferralAttachOutcome.attached);
  });

  test('Google signup: already signed in on the name step, so the code '
      'attaches right after that step saves', () async {
    signedIn = true;
    store.value = kPendingRavi;
    expect(await controller().attachPending(), ReferralAttachOutcome.attached);
    expect(repository.attached, ['NM7K2P9X']);
  });

  test('app restart between entering and attaching: a new controller over '
      'the same store still attaches, once', () async {
    store.value = kPendingRavi;
    // First process: killed before the member ever signed in.
    expect(
      await controller().attachPending(),
      ReferralAttachOutcome.notSignedIn,
    );
    // Second process, signed in (cold start with a restored session).
    signedIn = true;
    expect(await controller().attachPending(), ReferralAttachOutcome.attached);
    expect(
      await controller().attachPending(),
      ReferralAttachOutcome.nothingPending,
    );
    expect(repository.attached, hasLength(1));
  });
}

class _ThrowingStore extends InMemoryPendingReferralStore {
  @override
  PendingReferralCode? read() => throw StateError('storage not ready');
}
