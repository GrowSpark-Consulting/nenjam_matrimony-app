import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'package:nenjam_matrimony/features/registration/data/repositories/registration_repository.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/features/verification/domain/models/face_verification.dart';
import 'package:nenjam_matrimony/features/verification/domain/repositories/face_verification_repository.dart';
import 'package:nenjam_matrimony/features/verification/presentation/providers/face_verification_providers.dart';
import 'package:nenjam_matrimony/features/verification/presentation/providers/selfie_requirement_provider.dart';
import 'package:nenjam_matrimony/features/verification/presentation/widgets/face_verification_card.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';

class _Draft implements RegistrationRepository {
  _Draft(this.relation);
  final String relation;

  @override
  Future<Map<String, dynamic>> getDraft() async => {
    'data': {
      'basicDetails': {'profileCreatedFor': relation},
    },
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Face implements FaceVerificationRepository {
  static int calls = 0;

  @override
  Future<FaceVerificationState> getState() async {
    calls++;
    return const FaceVerificationState(
      status: FaceVerificationStatus.unverified,
      verifiedAt: null,
      canStart: true,
      blockedReason: null,
      attemptsRemainingToday: 3,
      retryAfter: null,
    );
  }

  @override
  Future<LivenessSessionTicket> startSession({required bool consent}) =>
      throw UnimplementedError();

  @override
  Future<FaceVerificationResult> complete({
    required String attemptId,
    ClientLivenessOutcome? clientOutcome,
    String? clientErrorCode,
  }) => throw UnimplementedError();
}

Future<void> _pumpCard(WidgetTester tester, String relation) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(_Draft(relation)),
        faceVerificationRepositoryProvider.overrideWithValue(_Face()),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: FaceVerificationCard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _Face.calls = 0);

  testWidgets('Myself sees the Face Match card and the status is requested', (
    tester,
  ) async {
    await _pumpCard(tester, 'Myself');
    expect(find.byType(Card), findsOneWidget);
    expect(_Face.calls, greaterThan(0));
  });

  for (final relation in [
    'Son',
    'Daughter',
    'Brother',
    'Sister',
    'Friend',
    'Relative',
  ]) {
    testWidgets('$relation sees no selfie control and no API is called', (
      tester,
    ) async {
      await _pumpCard(tester, relation);
      expect(find.byType(Card), findsNothing);
      expect(_Face.calls, 0);
    });
  }

  test('the requirement provider follows the saved draft', () async {
    for (final entry in {'Myself': true, 'Son': false, 'Friend': false}.entries) {
      final c = ProviderContainer(
        overrides: [
          registrationRepositoryProvider.overrideWithValue(_Draft(entry.key)),
        ],
      );
      addTearDown(c.dispose);
      expect(
        await c.read(selfieVerificationRequiredProvider.future),
        entry.value,
        reason: entry.key,
      );
      // Reads the shared dashboard draft — no second request of its own.
      expect(c.read(profileDraftResponseProvider).hasValue, isTrue);
    }
  });
}
