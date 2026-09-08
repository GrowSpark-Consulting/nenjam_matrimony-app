import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nenjam_matrimony/core/network/api_client.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/core/utils/birth_date.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/core/widgets/inputs/birth_date_field.dart';
import 'package:nenjam_matrimony/features/profile/domain/models/profile.dart';
import 'package:nenjam_matrimony/l10n/app_localizations.dart';
import 'package:nenjam_matrimony/features/registration/data/repositories/registration_repository.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/pages/onboarding_name_page.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';
import 'package:nenjam_matrimony/features/registration/presentation/widgets/step_basic_info.dart';

import 'onboarding_test_support.dart';

/// The date of birth, from the keystroke to the wire and back again.
///
/// The step tests prove the screen validates; the rule tests prove the rule is
/// right. Neither proves the thing that actually broke before: that the date a
/// member types is the date that reaches the API, and the date that comes back
/// from it is the date they see. That is a question about the *seam* — the
/// JSON body, the exact endpoint, the shape the backend returns — so this
/// drives the real [RegistrationRepository] over real Dio [Response] objects
/// and asserts on the bytes, rather than on a hand-built model.
///
/// What it cannot reach is Postgres. The backend half of the same walk —
/// `PATCH /profiles/draft/basic-details` through the DTO, the service and into
/// the column, then read back — is
/// `backend/apps/api/src/modules/profiles/tests/birth-date-end-to-end.integration.spec.ts`,
/// which runs against a real database. The two meet at the payloads asserted
/// here: `{"dob": "1998-08-15"}` out, `"1998-08-15T00:00:00.000Z"` back.
void main() {
  // ─── Flutter → API: what actually goes on the wire ──────────────────

  group('the request body', () {
    late _RecordingApiClient api;
    late RegistrationRepository repository;

    setUp(() {
      api = _RecordingApiClient();
      repository = RegistrationRepository(api);
    });

    test('carries the typed date as date-only YYYY-MM-DD', () async {
      await repository.updateBasicDetails(
        BasicDetails(
          firstName: 'Arjun',
          lastName: 'Krishnan',
          gender: 'Male',
          maritalStatus: 'Never Married',
          profileCreatedFor: 'Myself',
          dob: DateTime(1998, 8, 15),
        ),
      );

      // The endpoint the backend already had — no new route was introduced.
      expect(api.lastPath, '/profiles/draft/basic-details');
      expect(api.lastBody?['dob'], '1998-08-15');
      // No time, no zone, nothing for a timezone to act on.
      expect(api.lastBody?['dob'], isNot(contains('T')));
      expect(api.lastBody?['dob'], isNot(contains('Z')));
      // And the rest of the section still travels as the API's enum values.
      expect(api.lastBody?['gender'], 'MALE');
      expect(api.lastBody?['maritalStatus'], 'NEVER_MARRIED');
    });

    test('zero-pads single-digit days and months', () async {
      await repository.updateBasicDetails(
        BasicDetails(firstName: 'A', dob: DateTime(2004, 2, 9)),
      );
      // `2004-2-9` is not a date the DTO's four-digit-YYYY-MM-DD rule accepts.
      expect(api.lastBody?['dob'], '2004-02-09');
    });

    test('sends nothing for a date the member has not given', () async {
      await repository.updateBasicDetails(
        const BasicDetails(firstName: 'Arjun', lastName: 'Krishnan'),
      );
      expect(api.lastBody?.containsKey('dob'), isFalse);
    });

    test('is unaffected by the device timezone offset', () async {
      // DateTime(1998, 8, 15) is local midnight. Serializing it as an instant
      // — which `toIso8601String()` did — hands the server 1998-08-14T18:30Z
      // on an IST device. birthDateToWire reads the calendar fields instead,
      // so the same three numbers travel from every device on earth.
      final local = DateTime(1998, 8, 15);
      await repository.updateBasicDetails(BasicDetails(dob: local));
      expect(api.lastBody?['dob'], '1998-08-15');
      // Whatever this machine's offset, the date sent is the date typed —
      // even where the instant behind it falls on the 14th in UTC.
      expect(birthDateToWire(local), '1998-08-15');
    });
  });

  // ─── API → Flutter: what comes back ─────────────────────────────────

  group('the response', () {
    test('reads the profile date back as the day that was sent', () {
      // `GET /profiles/me` serializes `user_profiles.dob` with
      // `Date.toISOString()`, and the write now stores UTC midnight — so this
      // is the exact string the backend returns for a member who typed
      // 15 / 08 / 1998.
      final profile = Profile.fromJson(_profileJson('1998-08-15T00:00:00.000Z'));
      expect(profile.dob, DateTime(1998, 8, 15));
      expect(birthDateToWire(profile.dob), '1998-08-15');
    });

    test('reads a draft date back as the day that was sent', () {
      final draft = ProfileDraft.fromJson({
        'basicDetails': {'firstName': 'Arjun', 'dob': '1998-08-15'},
      });
      expect(draft.basicDetails.dob, DateTime(1998, 8, 15));
    });

    test('still loads a draft saved by an older build', () {
      // The two shapes in `draft_data` today. A member mid-signup when this
      // shipped must not lose the answer they already gave.
      for (final stored in const [
        '1998-08-15T00:00:00.000Z',
        '1998-08-15T00:00:00.000',
        '1998-08-15T00:00:00+05:30',
      ]) {
        final draft = ProfileDraft.fromJson({
          'basicDetails': {'firstName': 'Arjun', 'dob': stored},
        });
        expect(draft.basicDetails.dob, DateTime(1998, 8, 15), reason: stored);
        // And re-saving it normalizes the draft to the date-only form.
        expect(draft.basicDetails.toJson()['dob'], '1998-08-15');
      }
    });

    test('round-trips without drifting a day', () {
      final typed = DateTime(1998, 8, 15);
      final sent = birthDateToWire(typed);
      // What the backend stores and returns for that string.
      final returned = '${sent}T00:00:00.000Z';
      expect(Profile.fromJson(_profileJson(returned)).dob, typed);
    });
  });

  // ─── Editing an existing date, and surviving a restart ──────────────

  group('the Edit Profile wizard', () {
    testWidgets('shows a stored date in the same three boxes', (tester) async {
      // The wizard step and the onboarding step are the same field. A member
      // who edits their profile must not meet a different input, or a
      // different rule, from the one they filled in at signup.
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StepBasicInfo(
              details: BasicDetails(dob: DateTime(1995, 3, 21)),
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NmBirthDateField), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
      expect(find.text('03'), findsOneWidget);
      expect(find.text('1995'), findsOneWidget);

      // RegistrationHelperTip fades in through flutter_animate, whose ticker
      // outlives the tree if the test ends mid-animation. Let it finish.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('emits an edited date in the same date-only wire format', (
      tester,
    ) async {
      BasicDetails? emitted;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StepBasicInfo(
              details: BasicDetails(dob: DateTime(1995, 3, 21)),
              onChanged: (d) => emitted = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boxes = find.descendant(
        of: find.byType(NmBirthDateField),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(boxes.at(0), '15');
      await tester.enterText(boxes.at(1), '08');
      await tester.enterText(boxes.at(2), '1998');
      await tester.pumpAndSettle();

      expect(emitted?.dob, DateTime(1998, 8, 15));
      // The one serializer, shared with onboarding — an edit reaches
      // PATCH /profiles/draft/basic-details in exactly the shape a signup does.
      expect(emitted?.toJson()['dob'], '1998-08-15');
    });

    testWidgets('refuses to emit a date the rule rejects', (tester) async {
      BasicDetails? emitted;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StepBasicInfo(
              details: const BasicDetails(),
              onChanged: (d) => emitted = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boxes = find.descendant(
        of: find.byType(NmBirthDateField),
        matching: find.byType(TextFormField),
      );
      // 31 February, then someone under 21 — neither may become a stored dob.
      await tester.enterText(boxes.at(0), '31');
      await tester.enterText(boxes.at(1), '02');
      await tester.enterText(boxes.at(2), '2003');
      await tester.pumpAndSettle();
      expect(emitted?.dob, isNull);
      expect(find.text('Please enter a valid date of birth.'), findsOneWidget);

      await tester.enterText(boxes.at(0), '15');
      await tester.enterText(boxes.at(1), '08');
      await tester.enterText(
        boxes.at(2),
        '${DateTime.now().year - 10}',
      );
      await tester.pumpAndSettle();
      expect(emitted?.dob, isNull);
      expect(
        find.text('You must be at least 21 years old to register.'),
        findsOneWidget,
      );
    });
  });

  group('surviving an app restart', () {
    test('the date survives the disk snapshot verbatim', () {
      // RegistrationNotifier._snapshot writes jsonEncode(state.toJson()) to
      // SharedPreferences; splash_provider reads it back through
      // ProfileDraft.fromJson on the next launch. This is that exact pair.
      final before = ProfileDraft(
        basicDetails: BasicDetails(
          firstName: 'Arjun',
          lastName: 'Krishnan',
          dob: DateTime(1998, 8, 15),
        ),
      );

      final onDisk = jsonEncode(before.toJson());
      // Stored date-only, so nothing on disk can be re-read in another zone.
      expect(onDisk, contains('"dob":"1998-08-15"'));
      expect(onDisk, isNot(contains('T00:00:00')));

      final after = ProfileDraft.fromJson(
        jsonDecode(onDisk) as Map<String, dynamic>,
      );
      expect(after.basicDetails.dob, DateTime(1998, 8, 15));
      expect(after.basicDetails.dob, before.basicDetails.dob);
    });

    test('a snapshot written by an older build still restores', () {
      // A member who was mid-signup when this shipped has a legacy timestamp
      // sitting in SharedPreferences. It must still open on their answer.
      for (final legacy in const [
        '1998-08-15T00:00:00.000Z',
        '1998-08-15T00:00:00.000',
        '1998-08-15T00:00:00+05:30',
      ]) {
        final restored = ProfileDraft.fromJson(
          jsonDecode('{"basicDetails":{"dob":"$legacy"}}')
              as Map<String, dynamic>,
        );
        expect(restored.basicDetails.dob, DateTime(1998, 8, 15), reason: legacy);
        // And the next snapshot writes it back normalized.
        expect(
          jsonEncode(restored.toJson()),
          contains('"dob":"1998-08-15"'),
          reason: legacy,
        );
      }
    });

    test('an unanswered date restores as unanswered, not as an epoch', () {
      final restored = ProfileDraft.fromJson(
        jsonDecode('{"basicDetails":{"firstName":"Arjun"}}')
            as Map<String, dynamic>,
      );
      expect(restored.basicDetails.dob, isNull);
      expect(jsonEncode(restored.toJson()), isNot(contains('"dob"')));
    });
  });

  // ─── The rejection path, on screen ──────────────────────────────────

  group('a backend rejection', () {
    GoRouter buildRouter() => GoRouter(
          initialLocation: RouteNames.onboardingNameDob,
          routes: [
            GoRoute(
              path: RouteNames.onboardingNameDob,
              builder: (context, state) => const OnboardingNamePage(),
            ),
            GoRoute(
              path: RouteNames.onboardingReligion,
              builder: (context, state) =>
                  const Scaffold(body: Text('religion-reached')),
            ),
            GoRoute(
              path: RouteNames.createProfileFor,
              builder: (context, state) =>
                  const Scaffold(body: Text('profile-for-reached')),
            ),
          ],
        );

    ProviderContainer containerWith(RecordingRegistrationRepository repo) =>
        ProviderContainer(overrides: [
          registrationRepositoryProvider.overrideWithValue(repo),
          firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
        ]);

    testWidgets('is shown to the member in the API\'s own words', (
      tester,
    ) async {
      useTallSurface(tester);
      // What the API answers when its check refuses a date the client's did
      // not — an older build, or a value typed either side of the UTC day
      // boundary. The member has to be told which, or the step is a dead end.
      final container = containerWith(
        _RejectingRepository(
          400,
          'You must be at least 21 years old to register.',
        ),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();
      await fillNameStep(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(
        find.text('You must be at least 21 years old to register.'),
        findsOneWidget,
      );
      // Told why, and kept on the step rather than advanced past a save that
      // did not happen.
      expect(find.text('religion-reached'), findsNothing);
    });

    testWidgets('keeps the generic line for a server fault', (tester) async {
      useTallSurface(tester);
      // A 500 body is written for an operator. Showing it to a member would
      // be the "expose technical exceptions" failure in the other direction.
      final container = containerWith(
        _RejectingRepository(500, 'ECONNREFUSED prisma pool exhausted'),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();
      await fillNameStep(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ECONNREFUSED'), findsNothing);
      expect(find.text('religion-reached'), findsNothing);
    });

    testWidgets('a successful save still advances', (tester) async {
      useTallSurface(tester);
      // The regression guard for the failure flag this path hangs off: if a
      // success were ever read as a failure, onboarding would stop dead here.
      final container = containerWith(RecordingRegistrationRepository());
      addTearDown(container.dispose);

      await tester.pumpWidget(harness(container, buildRouter()));
      await tester.pumpAndSettle();
      await fillNameStep(tester);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('religion-reached'), findsOneWidget);
    });
  });
}

Map<String, dynamic> _profileJson(String dob) => {
      'firstName': 'Arjun',
      'lastName': 'Krishnan',
      'dob': dob,
      'gender': 'MALE',
      'maritalStatus': 'NEVER_MARRIED',
      'religion': 'Hindu',
      'photos': <dynamic>[],
      'completion': {
        'percentage': 0,
        'completedSections': <dynamic>[],
        'missingSections': <dynamic>[],
      },
    };

/// Captures the body of the PATCH the repository actually sends, so the
/// assertion is on the wire format rather than on the model behind it.
class _RecordingApiClient implements ApiClient {
  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    lastPath = path;
    lastBody = data as Map<String, dynamic>?;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: <String, dynamic>{'data': <String, dynamic>{}} as T,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fails the basic-details save the way the API does — through the same
/// `unwrapOrThrow` path a real 4xx body takes.
class _RejectingRepository extends RecordingRegistrationRepository {
  _RejectingRepository(this.status, this.message);

  final int status;
  final String message;

  @override
  Future<void> updateBasicDetails(
    BasicDetails details, {
    bool skipMaterialize = false,
  }) async {
    throw RegistrationApiException(status, message);
  }
}
