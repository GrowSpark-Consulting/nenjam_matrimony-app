import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/utils/post_auth_destination.dart';
import 'package:nenjam_matrimony/features/profile/domain/models/profile.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/profile/data/repositories/api_profile_repository.dart';
import 'package:nenjam_matrimony/features/profile/presentation/providers/profile_providers.dart';
import 'package:nenjam_matrimony/features/registration/data/repositories/registration_repository.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'post_auth_google_support.dart';

/// Where a Google account lands, for each of the four states the flow has to
/// tell apart.
///
/// Both Google buttons run the same credential exchange — there is only one —
/// so what separates Log In from Sign Up is the intent the button records
/// plus the account state the backend reports. These pin the second half:
/// given a Google session, which route does the resolver produce?
///
/// The first half (the intent itself) is pinned in
/// google_sign_in_controller_test.dart.
void main() {
  ProviderContainer containerFor({
    required Future<Map<String, dynamic>> Function() draft,
    required bool hasFinalizedProfile,
    bool contactable = true,
  }) {
    final container = ProviderContainer(
      overrides: [
        registrationRepositoryProvider
            .overrideWithValue(_DraftOnlyRepository(draft)),
        profileRepositoryProvider
            .overrideWithValue(_ProfileRepository(hasFinalizedProfile)),
        firebaseAuthServiceProvider.overrideWithValue(
          GoogleSignedInAuthService(contactable: contactable),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<String> resolve(ProviderContainer c) =>
      c.read(postAuthDestinationProvider).resolve();

  // ─── State 4: already completed ─────────────────────────────────────

  test('an established Google member goes straight to Discover', () async {
    // `GET /profiles/me` answering with a row is the whole signal: the
    // backend writes one only once registration genuinely produced a
    // profile. Nothing below it is even consulted.
    final container = containerFor(
      draft: () async => throw StateError('the draft must not be needed'),
      hasFinalizedProfile: true,
    );

    final route = await resolve(container);
    expect(route, RouteNames.discover);
    // The three assertions that matter for "Log In must not become signup".
    expect(route, isNot(RouteNames.createProfileFor));
    expect(route, isNot(RouteNames.onboardingNameDob));
    expect(route, isNot(RouteNames.onboardingVerifyMobile));
  });

  test('an established member is never made to register a second time',
      () async {
    // Same account, arriving through the SIGN UP button instead. Signup
    // intent does not mean "make a new profile" — it means "this member
    // believes they are new", and the account state overrules that.
    final container = containerFor(
      draft: () async => throw StateError('the draft must not be needed'),
      hasFinalizedProfile: true,
    );
    expect(await resolve(container), RouteNames.discover);
  });

  // ─── State 2: brand new ─────────────────────────────────────────────

  test('a brand-new Google account opens Profile For', () async {
    final container = containerFor(
      draft: () async => emptyDraft(),
      hasFinalizedProfile: false,
    );
    expect(await resolve(container), RouteNames.createProfileFor);
  });

  test('a brand-new Google account gets the full onboarding, not a short one',
      () async {
    // Google supplies an identity, not a matrimonial profile. Every field
    // the other two signup methods collect is still outstanding here, which
    // is what makes the first step Profile For rather than Discover.
    final container = containerFor(
      draft: () async => emptyDraft(),
      hasFinalizedProfile: false,
    );
    expect(await resolve(container), RouteNames.createProfileFor);
    expect(
      RouteNames.publicRoutes,
      contains(RouteNames.onboardingVerifyMobile),
      reason: 'the dummy-OTP step is part of the Google signup path too',
    );
  });

  // ─── State 3: partially onboarded ───────────────────────────────────

  group('a partially onboarded Google account resumes its own step', () {
    final cases = <String, (Map<String, dynamic>, String)>{
      'nothing but the relation': (
        googleDraft(gender: ''),
        RouteNames.createProfileFor,
      ),
      'Profile For answered': (
        googleDraft(firstName: '', lastName: '', dob: ''),
        RouteNames.onboardingNameDob,
      ),
      'name answered': (
        googleDraft(religion: '', community: '', livingIn: ''),
        RouteNames.onboardingReligion,
      ),
      'religion answered': (
        googleDraft(state: '', city: '', caste: '', motherTongue: ''),
        RouteNames.profileBasics,
      ),
      'basics answered': (
        googleDraft(maritalStatus: '', height: ''),
        RouteNames.onboardingMarital,
      ),
      'marital answered': (
        googleDraft(qualification: ''),
        RouteNames.onboardingEducation,
      ),
      'qualification answered': (
        googleDraft(annualIncome: ''),
        RouteNames.onboardingIncome,
      ),
      'income answered': (googleDraft(aboutMe: ''), RouteNames.onboardingAbout),
    };

    for (final entry in cases.entries) {
      test(entry.key, () async {
        final (draft, expected) = entry.value;
        final container = containerFor(
          draft: () async => draft,
          hasFinalizedProfile: false,
        );
        expect(
          await resolve(container),
          expected,
          reason: '${entry.key} must resume exactly its own step, never '
              'restart onboarding',
        );
      });
    }
  });

  test('a Google signup that has not reached Email + Mobile is sent there',
      () async {
    // Google supplies an address but never a mobile number, and the flow
    // asks for both mid-onboarding. `contactable: false` is what a Google
    // account actually looks like before that step.
    final container = containerFor(
      draft: () async => googleDraft(state: '', city: '', caste: '',
          motherTongue: ''),
      hasFinalizedProfile: false,
      contactable: false,
    );
    expect(await resolve(container), RouteNames.onboardingContact);
  });

  test('an established member is NOT asked for contact details again',
      () async {
    // The same account once registration is finished. A finalized profile
    // short-circuits every onboarding gate, which is what keeps a Google
    // login out of signup entirely.
    final container = containerFor(
      draft: () async => throw StateError('the draft must not be needed'),
      hasFinalizedProfile: true,
      contactable: false,
    );
    expect(await resolve(container), RouteNames.discover);
  });

  test('resuming rehydrates the draft rather than starting from blank',
      () async {
    // What makes "resume" real: the answers already given are put back into
    // the provider, so the step reopens on them. Without this a resumed
    // Google signup would show empty fields and the next save would
    // overwrite good data with blanks.
    final container = containerFor(
      draft: () async => googleDraft(qualification: '', annualIncome: '',
          aboutMe: ''),
      hasFinalizedProfile: false,
    );

    expect(await resolve(container), RouteNames.onboardingEducation);

    final draft = container.read(registrationProvider);
    expect(draft.basicDetails.profileCreatedFor, 'Myself');
    expect(draft.basicDetails.gender, 'Male');
    expect(draft.basicDetails.firstName, 'Arjun');
    expect(draft.religionDetails.religion, 'Hindu');
    expect(draft.religionDetails.caste, 'Vellalar');
    expect(draft.languageDetails.motherTongue, 'Tamil');
    expect(draft.locationDetails.city, 'Chennai');
  });

  // ─── No duplicate profile ───────────────────────────────────────────

  test('resolving twice for the same account produces no second registration',
      () async {
    var draftReads = 0;
    final container = containerFor(
      draft: () async {
        draftReads++;
        return googleDraft();
      },
      hasFinalizedProfile: false,
    );

    // A fully answered draft resolves to the OTP step's successor, not back
    // to Profile For — so re-entering through either Google button cannot
    // start a second profile for an account that already has one in flight.
    expect(await resolve(container), RouteNames.discover);
    expect(await resolve(container), RouteNames.discover);
    expect(draftReads, 2, reason: 'each resolve reads state, none writes it');
  });
}

/// Serves a canned draft and refuses everything else — the resolver must not
/// be writing anything while deciding where to send someone.
class _DraftOnlyRepository implements RegistrationRepository {
  _DraftOnlyRepository(this._draft);

  final Future<Map<String, dynamic>> Function() _draft;

  @override
  Future<Map<String, dynamic>> getDraft() => _draft();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `GET /profiles/me`: a row for an established member, a throw for everyone
/// else — exactly the 404 the real endpoint answers with.
class _ProfileRepository implements ApiProfileRepository {
  _ProfileRepository(this.exists);

  final bool exists;

  @override
  Future<Profile> getMyProfile() async {
    if (!exists) throw Exception('404 — no profile for this account');
    // Field values are irrelevant: the resolver only asks whether the row
    // exists at all. fromJson fills every gap.
    return Profile.fromJson(const {
      'firstName': 'Existing',
      'currentState': 'Karnataka',
      'currentCity': 'Bangalore',
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
