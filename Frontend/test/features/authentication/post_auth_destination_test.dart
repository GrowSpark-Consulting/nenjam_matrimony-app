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
/// the section editor, never in Discover.
///
/// Onboarding is two screens: Profile For, then Location & Sub-community.
/// [PostAuthDestination] is the only thing that decides which of them (if
/// either) a returning user still owes, and it must never send anyone to
/// [RouteNames.registrationWizard] — that screen belongs to Edit Profile
/// now, and the 13-step signup flow it used to host no longer exists.
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
    this.phoneNumber = '',
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

  /// Empty by default, and empty is the realistic case: nothing in the app
  /// links a phone credential while the OTP is the development verifier,
  /// so no account this app creates ever carries one.
  @override
  final String? phoneNumber;

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

/// A `GET /profiles/draft` body. A null section is omitted entirely, which
/// is what the backend returns for a freshly created row.
Map<String, dynamic> _draftBody({
  bool isComplete = false,
  int currentStep = 0,
  Map<String, dynamic>? basicDetails,
  Map<String, dynamic>? locationDetails,
  Map<String, dynamic>? religionDetails,
  Map<String, dynamic>? physicalDetails,
  Map<String, dynamic>? educationDetails,
  Map<String, dynamic>? lifestyleDetails,
}) {
  return {
    'currentStep': currentStep,
    'totalSteps': ProfileDraft.totalSteps,
    'isComplete': isComplete,
    'data': {
      if (basicDetails != null) 'basicDetails': basicDetails,
      if (locationDetails != null) 'locationDetails': locationDetails,
      if (religionDetails != null) 'religionDetails': religionDetails,
      if (physicalDetails != null) 'physicalDetails': physicalDetails,
      if (educationDetails != null) 'educationDetails': educationDetails,
      if (lifestyleDetails != null) 'lifestyleDetails': lifestyleDetails,
    },
  };
}

/// A draft with every answer onboarding asks of it. Each parameter can be
/// blanked to leave exactly one step outstanding, which is how the tests
/// below check one gate at a time.
///
/// This covers every draft-backed step: Profile For (`relation`), Religion
/// (`religion` + `community` + `livingIn`), Location (`state` + `city`),
/// Marital (`maritalStatus` + `height`), Education (`qualification`),
/// Income (`annualIncome`) and About (`aboutMe`). Photos are not a gate —
/// they are optional. The Email + Mobile step is deliberately absent: its
/// answers reach neither the draft nor the account, which is why a draft
/// in this shape marks an account that has *finished* onboarding and must
/// never be asked for contact details again.
Map<String, dynamic> _answeredDraft({
  bool isComplete = false,
  String relation = 'Myself',
  String religion = 'Hindu',
  String community = 'Vellalar',
  String livingIn = 'India',
  String state = 'Tamil Nadu',
  String city = 'Chennai',
  String maritalStatus = 'Never Married',
  String height = '5\'9" (175 cm)',
  String qualification = 'B.E / B.Tech',
  String annualIncome = '10 - 20 Lakhs',
  String aboutMe = 'A short description.',
}) =>
    _draftBody(
      isComplete: isComplete,
      basicDetails: {
        'profileCreatedFor': relation,
        'maritalStatus': maritalStatus,
      },
      religionDetails: {'religion': religion, 'community': community},
      locationDetails: {
        'country': livingIn,
        'state': state,
        'city': city,
      },
      physicalDetails: {'height': height},
      educationDetails: {
        'qualification': qualification,
        'annualIncome': annualIncome,
      },
      lifestyleDetails: {'aboutMe': aboutMe},
    );

/// An account that does carry a linked number — what a real phone-auth
/// signup would produce once the mock verifier is replaced.
_FakeUser _contactableUser() => _FakeUser(phoneNumber: '+919876543210');

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
    test('"Myself" is a real choice, not a default, and opens the next step',
        () async {
      // The regression this whole change exists for: 'Myself' must be
      // treated as an answer when the user actually gave it...
      final container = _container(
        draft: () async => _draftBody(
          currentStep: 3,
          basicDetails: {'profileCreatedFor': 'Myself'},
        ),
      );
      expect(await _resolve(container), RouteNames.onboardingReligion);
      // ...and the draft is rehydrated, which is what lets each onboarding
      // screen reopen on whatever the backend already had.
      expect(
        container.read(registrationProvider).basicDetails.profileCreatedFor,
        'Myself',
      );
    });

    test('every other relation reaches the next step too', () async {
      for (final choice in ['Son', 'Daughter', 'Brother', 'Sister', 'Friend',
        'Relative']) {
        final container = _container(
          draft: () async =>
              _draftBody(basicDetails: {'profileCreatedFor': choice}),
        );
        expect(
          await _resolve(container),
          RouteNames.onboardingReligion,
          reason: '"$choice" is an explicit answer',
        );
      }
    });

    test('a fully answered onboarding opens the app', () async {
      final container = _container(
        draft: () async => _answeredDraft(),
        user: _contactableUser(),
      );
      expect(await _resolve(container), RouteNames.discover);
    });

    test('each unanswered step reopens that step and no other', () async {
      // One gate at a time, in the order the member meets them.
      final cases = <String, (Map<String, dynamic>, String)>{
        'no relation': (
          _answeredDraft(relation: ''),
          RouteNames.createProfileFor,
        ),
        'no religion': (
          _answeredDraft(religion: ''),
          RouteNames.onboardingReligion,
        ),
        'no community': (
          _answeredDraft(community: ''),
          RouteNames.onboardingReligion,
        ),
        'no country': (
          _answeredDraft(livingIn: ''),
          RouteNames.onboardingReligion,
        ),
        'no state': (_answeredDraft(state: ''), RouteNames.profileBasics),
        'no city': (_answeredDraft(city: ''), RouteNames.profileBasics),
        'whitespace city': (
          _answeredDraft(city: '   '),
          RouteNames.profileBasics,
        ),
        'no marital status': (
          _answeredDraft(maritalStatus: ''),
          RouteNames.onboardingMarital,
        ),
        'no height': (
          _answeredDraft(height: ''),
          RouteNames.onboardingMarital,
        ),
        'no qualification': (
          _answeredDraft(qualification: ''),
          RouteNames.onboardingEducation,
        ),
        'no annual income': (
          _answeredDraft(annualIncome: ''),
          RouteNames.onboardingIncome,
        ),
        'no description': (
          _answeredDraft(aboutMe: ''),
          RouteNames.onboardingAbout,
        ),
      };
      for (final entry in cases.entries) {
        final (draft, expected) = entry.value;
        final container = _container(
          draft: () async => draft,
          user: _contactableUser(),
        );
        expect(
          await _resolve(container),
          expected,
          reason: '${entry.key} must reopen exactly its own step',
        );
      }
    });

    test('an answered draft goes to Discover even with no number on the '
        'account', () async {
      // The regression this file now guards. `user.phoneNumber` is empty for
      // every account the app can create (nothing links a phone credential
      // while the OTP is the development verifier), so gating on it sent
      // every logged-in member to the Email + Mobile step forever. An
      // answered draft means onboarding is done; contact details are not
      // re-collected at login.
      final container = _container(draft: () async => _answeredDraft());
      expect(await _resolve(container), RouteNames.discover);
    });

    test('the removed 13-step wizard is never a destination', () async {
      // The guarantee the whole flow change rests on. Every draft shape the
      // resolver can meet, including the mid-wizard progress a pre-existing
      // account may still carry on the backend.
      final drafts = <Future<Map<String, dynamic>> Function()>[
        () async => _draftBody(),
        () async => _draftBody(currentStep: 7),
        () async => _draftBody(basicDetails: {'profileCreatedFor': 'Myself'}),
        () async => _answeredDraft(),
        () async => _answeredDraft(isComplete: true),
        () async => throw Exception('network down'),
      ];
      for (final draft in drafts) {
        for (final user in [_FakeUser(), _contactableUser()]) {
          final container = _container(draft: draft, user: user);
          expect(
            await _resolve(container),
            isNot(RouteNames.registrationWizard),
          );
        }
      }
    });

    test('a finished profile that answered onboarding goes to Discover',
        () async {
      final container = _container(
        draft: () async => _answeredDraft(isComplete: true),
        user: _contactableUser(),
      );
      expect(await _resolve(container), RouteNames.discover);
    });

    test('`isComplete` alone is not a pass through the onboarding gates',
        () async {
      // Deliberate: `isComplete` is the pre-onboarding wizard's verdict and
      // says nothing about whether these four steps were answered, so a
      // profile finalized before this flow existed is still asked for what
      // it never collected rather than waved straight through.
      final container = _container(
        draft: () async => _draftBody(
          isComplete: true,
          basicDetails: {'profileCreatedFor': 'Myself'},
        ),
      );
      expect(await _resolve(container), RouteNames.onboardingReligion);
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

  // ─── The Email + Mobile step ────────────────────────────────────────
  //
  // Login and signup meet at this gate, and only one of them belongs here.
  group('the Email + Mobile step is a signup gate, not a session gate', () {
    test('an established account never reaches it, on any login method',
        () async {
      // Email/password and Google both land here through _routeAfterLogin,
      // and a mobile login resolves no destination at all — so this one
      // assertion covers every Firebase-backed login the app offers.
      final container = _container(draft: () async => _answeredDraft());
      final route = await _resolve(container);

      expect(route, RouteNames.discover);
      expect(route, isNot(RouteNames.onboardingContact));
      expect(route, isNot(RouteNames.registrationLanding));
    });

    test('an account carrying a linked number also goes to Discover',
        () async {
      // The same answer once real phone auth is restored and the number is
      // on the account: the gate must not start firing again either way.
      final container = _container(
        draft: () async => _answeredDraft(),
        user: _contactableUser(),
      );
      expect(await _resolve(container), RouteNames.discover);
    });

    test('an unfinished signup still owes the step', () async {
      // Signup is untouched: religion answered, nothing after it, and no
      // contact details on record — exactly the member the screen exists
      // for. The draft-backed gates below it must not steal the step.
      final container = _container(
        draft: () async => _draftBody(
          basicDetails: {'profileCreatedFor': 'Myself'},
          religionDetails: {'religion': 'Hindu', 'community': 'Vellalar'},
          locationDetails: {'country': 'India'},
        ),
      );
      expect(await _resolve(container), RouteNames.onboardingContact);
    });

    test('the step still comes before the ones that follow it', () async {
      // Ordering is what makes signup linear. A member who has answered
      // religion but not basics owes contact first, not Profile Basics.
      final container = _container(
        draft: () async => _draftBody(
          basicDetails: {'profileCreatedFor': 'Myself'},
          religionDetails: {'religion': 'Hindu', 'community': 'Vellalar'},
          locationDetails: {'country': 'India'},
        ),
      );
      final route = await _resolve(container);
      expect(route, RouteNames.onboardingContact);
      expect(route, isNot(RouteNames.profileBasics));
    });
  });

}
