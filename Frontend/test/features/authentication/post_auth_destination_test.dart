import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/data/services/firebase_auth_service.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/utils/post_auth_destination.dart';
import 'package:nenjam_matrimony/features/registration/data/repositories/registration_repository.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

/// The rule under test: **a brand-new user who has never answered "who is
/// this profile for?" must always land on CreateProfileForPage** — never in
/// the wizard, never in Discover.
///
/// This used to be impossible to guarantee, because `BasicDetails` defaulted
/// `profileCreatedFor` to 'Myself'. An untouched draft was therefore
/// indistinguishable from one where the user had deliberately chosen
/// "Myself", so a new account could sail past the question and be registered
/// as themselves without ever being asked. The field now defaults to empty,
/// which is what these tests pin down.

// ─── Fakes ───────────────────────────────────────────────────────────
//
// `noSuchMethod` forwarding lets each fake implement only the members the
// resolver touches, without needing a live FirebaseAuth or Dio client.

class _FakeUserMetadata implements UserMetadata {
  _FakeUserMetadata(this.creationTime, this.lastSignInTime);

  @override
  final DateTime? creationTime;
  @override
  final DateTime? lastSignInTime;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUser implements User {
  _FakeUser({
    this.emailVerified = true,
    DateTime? createdAt,
    DateTime? lastSignInAt,
  }) : metadata = _FakeUserMetadata(
         createdAt ?? DateTime(2020, 1, 1),
         // Far apart by default: an established account, so a failed draft
         // lookup falls back to Discover rather than the new-user path.
         lastSignInAt ?? DateTime(2024, 6, 1),
       );

  /// Non-empty throughout: it is what makes [emailVerified] a gate the
  /// resolver actually applies (a phone-only account has no address to check).
  @override
  final String? email = 'arjun@example.com';
  @override
  final bool emailVerified;
  @override
  final UserMetadata metadata;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthService implements FirebaseAuthService {
  _FakeAuthService(this.currentUser);

  @override
  final User? currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRegistrationRepository implements RegistrationRepository {
  _FakeRegistrationRepository(this._draft);

  final Future<Map<String, dynamic>> Function() _draft;

  @override
  Future<Map<String, dynamic>> getDraft() => _draft();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container({
  required Future<Map<String, dynamic>> Function() draft,
  User? user,
}) {
  final container = ProviderContainer(
    overrides: [
      firebaseAuthServiceProvider.overrideWithValue(
        _FakeAuthService(user ?? _FakeUser()),
      ),
      registrationRepositoryProvider.overrideWithValue(
        _FakeRegistrationRepository(draft),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A `GET /profiles/draft` body. [basicDetails] null omits the section
/// entirely, which is what the backend returns for a freshly created row.
Map<String, dynamic> _draftBody({
  bool isComplete = false,
  int currentStep = 0,
  Map<String, dynamic>? basicDetails,
}) {
  return {
    'currentStep': currentStep,
    'totalSteps': ProfileDraft.totalSteps,
    'isComplete': isComplete,
    'data': {if (basicDetails != null) 'basicDetails': basicDetails},
  };
}

Future<String> _resolve(ProviderContainer c) =>
    c.read(postAuthDestinationProvider).resolve();

void main() {
  group('BasicDetails.profileCreatedFor represents "not chosen"', () {
    test('a fresh draft holds no choice at all', () {
      expect(const BasicDetails().profileCreatedFor, isEmpty);
      expect(const ProfileDraft().basicDetails.profileCreatedFor, isEmpty);
    });

    test('an absent field stays empty rather than becoming "Myself"', () {
      expect(BasicDetails.fromJson(const {}).profileCreatedFor, isEmpty);
      expect(
        BasicDetails.fromJson(const {'firstName': 'Arjun'}).profileCreatedFor,
        isEmpty,
        reason: 'a partially filled draft must not fabricate a relation',
      );
    });

    test('an explicit choice survives the round trip', () {
      for (final choice in ['Myself', 'Son', 'Daughter', 'Relative']) {
        final parsed = BasicDetails.fromJson({'profileCreatedFor': choice});
        expect(parsed.profileCreatedFor, choice);
        expect(parsed.toJson()['profileCreatedFor'], choice);
      }
    });

    test('an unset value is never sent to the backend as a choice', () {
      expect(
        const BasicDetails().toJson().containsKey('profileCreatedFor'),
        isFalse,
      );
    });

    test('basic details are incomplete until the question is answered', () {
      final answered = BasicDetails(
        firstName: 'Arjun',
        lastName: 'Krishnan',
        gender: 'Male',
        maritalStatus: 'Never Married',
        dob: DateTime(1996, 4, 12),
        profileCreatedFor: 'Myself',
      );
      expect(answered.isComplete, isTrue);
      expect(answered.copyWith(profileCreatedFor: '').isComplete, isFalse);
    });
  });

  group('PostAuthDestination sends an unanswered user to Profile For', () {
    test('a brand-new draft with no basicDetails section', () async {
      final container = _container(draft: () async => _draftBody());
      expect(await _resolve(container), RouteNames.createProfileFor);
    });

    test('a draft whose basicDetails omit the relation', () async {
      final container = _container(
        draft: () async => _draftBody(
          basicDetails: {'firstName': 'Arjun', 'lastName': 'Krishnan'},
        ),
      );
      expect(await _resolve(container), RouteNames.createProfileFor);
    });

    test('an empty-string relation', () async {
      final container = _container(
        draft: () async => _draftBody(basicDetails: {'profileCreatedFor': ''}),
      );
      expect(await _resolve(container), RouteNames.createProfileFor);
    });

    test('a whitespace-only relation', () async {
      final container = _container(
        draft: () async =>
            _draftBody(basicDetails: {'profileCreatedFor': '   '}),
      );
      expect(await _resolve(container), RouteNames.createProfileFor);
    });

    test('an entirely empty response body', () async {
      // getDraft() returns {} when the backend sends no payload.
      final container = _container(draft: () async => <String, dynamic>{});
      expect(await _resolve(container), RouteNames.createProfileFor);
    });

    test('a mid-wizard draft that still never answered the question', () async {
      // The strongest form of the rule: progress through the wizard does not
      // buy a bypass. Without an answer the user goes back to the question.
      final container = _container(
        draft: () async => _draftBody(
          currentStep: 5,
          basicDetails: {'firstName': 'Arjun', 'gender': 'MALE'},
        ),
      );
      expect(await _resolve(container), RouteNames.createProfileFor);
    });

    test('a brand-new account whose draft lookup fails', () async {
      final now = DateTime.now();
      final container = _container(
        draft: () async => throw Exception('network down'),
        user: _FakeUser(createdAt: now, lastSignInAt: now),
      );
      expect(await _resolve(container), RouteNames.createProfileFor);
    });
  });

  group('PostAuthDestination honours an explicit answer', () {
    test('"Myself" is a real choice, not a default, and resumes the wizard',
        () async {
      // The regression this whole change exists for: 'Myself' must be
      // treated as an answer when the user actually gave it...
      final container = _container(
        draft: () async => _draftBody(
          currentStep: 3,
          basicDetails: {'profileCreatedFor': 'Myself'},
        ),
      );
      expect(await _resolve(container), RouteNames.registrationWizard);
      // ...and the wizard resumes on the step the backend recorded.
      expect(container.read(registrationProvider).currentStep, 3);
      expect(
        container.read(registrationProvider).basicDetails.profileCreatedFor,
        'Myself',
      );
    });

    test('every other relation resumes the wizard too', () async {
      for (final choice in ['Son', 'Daughter', 'Brother', 'Sister', 'Friend',
        'Relative']) {
        final container = _container(
          draft: () async =>
              _draftBody(basicDetails: {'profileCreatedFor': choice}),
        );
        expect(
          await _resolve(container),
          RouteNames.registrationWizard,
          reason: '"$choice" is an explicit answer',
        );
      }
    });

    test('a completed profile goes to Discover, never back to the question',
        () async {
      final container = _container(
        draft: () async => _draftBody(
          isComplete: true,
          basicDetails: {'profileCreatedFor': 'Myself'},
        ),
      );
      expect(await _resolve(container), RouteNames.discover);
    });

    test('an unverified email still wins over everything else', () async {
      final container = _container(
        draft: () async => _draftBody(),
        user: _FakeUser(emailVerified: false),
      );
      expect(await _resolve(container), RouteNames.verifyEmail);
    });

    test('a signed-out caller is sent to the landing screen', () async {
      // Built directly rather than via _container, whose `user` parameter
      // falls back to a signed-in fake when null.
      final signedOut = ProviderContainer(
        overrides: [
          firebaseAuthServiceProvider.overrideWithValue(_FakeAuthService(null)),
          registrationRepositoryProvider.overrideWithValue(
            _FakeRegistrationRepository(() async => _draftBody()),
          ),
        ],
      );
      addTearDown(signedOut.dispose);
      expect(await _resolve(signedOut), RouteNames.registrationLanding);
    });
  });
}
