import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/core/router/route_names.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/onboarding_forms.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// The signup flow as one thing, rather than eleven screens each tested
/// alone.
///
/// Every step's own screen test asserts its widgets and its gate; those pass
/// perfectly well while the *chain* is broken — a step that writes to the
/// wrong draft section, a Back that resets the wizard, a final flush that
/// omits a NOT NULL column. All three have happened here. So this walks the
/// flow the way a member does, in order, through the same notifier methods
/// the screens call, and asserts that what arrives at the end is a draft the
/// backend can actually turn into a `user_profiles` row.
void main() {
  ProviderContainer containerWith(RecordingRegistrationRepository repository) {
    return ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(repository),
        firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
      ],
    );
  }

  /// Walks every onboarding step in flow order, through the notifier methods
  /// the screens' Continue buttons call. Returns the container so a test can
  /// assert on the draft the walk produced.
  Future<void> completeOnboarding(ProviderContainer container) async {
    final notifier = container.read(registrationProvider.notifier);

    // 1 — Profile For + Gender.
    notifier.applyProfileFor(
      const ProfileForForm(profileCreatedFor: 'Myself', gender: 'Male'),
    );

    // 2 — Your name + date of birth.
    await notifier.applyOnboardingName(
      const OnboardingNameForm(
        firstName: 'Arjun',
        lastName: 'Krishnan',
        day: '05',
        month: '02',
        year: '1998',
      ),
    );

    // 3 — Religion. Caste and mother tongue are no longer asked here; they
    // moved to step 5 with the fields themselves.
    await notifier.applyOnboardingReligion(
      const OnboardingReligionForm(
        religion: 'Hindu',
        community: 'Vellalar',
        livingIn: 'India',
      ),
    );

    // 4 — Email + mobile. Held on the device, not on the draft: the Firebase
    // account is where these two belong, and there is no account yet.
    await notifier.applyOnboardingContact(
      email: 'arjun@example.com',
      phoneE164: '+919876543210',
    );

    // 5 — State, city and sub-community.
    await notifier.applyProfileBasics(
      const ProfileBasicsForm(
        state: 'Tamil Nadu',
        city: 'Chennai',
        subCommunity: 'Iyer',
      ),
    );

    // 6 — Marital status, height, diet.
    await notifier.applyOnboardingMarital(
      const OnboardingMaritalForm(
        maritalStatus: 'Never Married',
        height: "5' 8\"",
        diet: 'Vegetarian',
      ),
    );

    // 7 — Highest qualification.
    await notifier.applyOnboardingEducation(
      const OnboardingEducationForm(qualification: 'B.E / B.Tech'),
    );

    // 8 — Annual income.
    await notifier.applyOnboardingIncome(
      const OnboardingIncomeForm(annualIncome: 'Rs. 10 - 15 Lakhs'),
    );

    // 9 — Photos. Nothing to assert on the draft: PhotoController uploads to
    // storage and persists the returned key itself, which is why photos are
    // not a gate and not part of this draft walk.

    // 10 — About yourself.
    await notifier.applyOnboardingAbout('I enjoy long walks and Carnatic music.');
  }

  test('every step lands on the draft section that owns it', () async {
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    await completeOnboarding(container);
    final draft = container.read(registrationProvider);

    // The mapping onto the sections `writeProfileFromDraft` reads. A step
    // writing to the wrong section is invisible on its own screen and fatal
    // at materialization time.
    expect(draft.basicDetails.profileCreatedFor, 'Myself');
    expect(draft.basicDetails.firstName, 'Arjun');
    expect(draft.basicDetails.lastName, 'Krishnan');
    expect(draft.basicDetails.dob, DateTime(1998, 2, 5));
    expect(draft.basicDetails.gender, 'Male');
    expect(draft.basicDetails.maritalStatus, 'Never Married');
    expect(draft.religionDetails.religion, 'Hindu');
    expect(draft.religionDetails.community, 'Vellalar');
    expect(draft.religionDetails.subCaste, 'Iyer');
    expect(draft.locationDetails.country, 'India');
    // Not collected anywhere in onboarding any more.
    expect(draft.religionDetails.caste, isEmpty);
    expect(draft.languageDetails.motherTongue, isEmpty);
    expect(draft.locationDetails.state, 'Tamil Nadu');
    expect(draft.locationDetails.city, 'Chennai');
    expect(draft.physicalDetails.height, "5' 8\"");
    expect(draft.lifestyleDetails.eatingHabit, 'Vegetarian');
    expect(draft.educationDetails.qualification, 'B.E / B.Tech');
    expect(draft.educationDetails.annualIncome, 'Rs. 10 - 15 Lakhs');
    expect(
      draft.lifestyleDetails.aboutMe,
      'I enjoy long walks and Carnatic music.',
    );
  });

  test('the completed draft satisfies every gate, so the flow ends at '
      'Discover', () async {
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    await completeOnboarding(container);
    final draft = container.read(registrationProvider);

    // The same forms PostAuthDestination rebuilds to decide whether to re-ask
    // a step. All complete means no gate can send this member backwards —
    // which is the difference between finishing signup and looping in it.
    expect(
      OnboardingNameForm.fromDraft(
        firstName: draft.basicDetails.firstName,
        lastName: draft.basicDetails.lastName,
        dob: draft.basicDetails.dob,
      ).isComplete,
      isTrue,
    );
    expect(
      ProfileForForm(
        profileCreatedFor: draft.basicDetails.profileCreatedFor,
        gender: draft.basicDetails.gender,
      ).isComplete,
      isTrue,
    );
    expect(
      OnboardingReligionForm(
        religion: draft.religionDetails.religion,
        community: draft.religionDetails.community,
        livingIn: draft.locationDetails.country,
      ).isComplete,
      isTrue,
    );
    expect(
      ProfileBasicsForm(
        state: draft.locationDetails.state,
        city: draft.locationDetails.city,
      ).isComplete,
      isTrue,
    );
    expect(
      OnboardingMaritalForm(
        maritalStatus: draft.basicDetails.maritalStatus,
        height: draft.physicalDetails.height,
      ).isComplete,
      isTrue,
    );
    expect(
      OnboardingEducationForm(
        qualification: draft.educationDetails.qualification,
      ).isComplete,
      isTrue,
    );
    expect(
      OnboardingIncomeForm(
        annualIncome: draft.educationDetails.annualIncome,
      ).isComplete,
      isTrue,
    );
    expect(draft.lifestyleDetails.aboutMe.trim(), isNotEmpty);
  });

  test('gender is answered on step 1 and survives every later step',
      () async {
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    await completeOnboarding(container);

    // One gender value, set once, on `BasicDetails.gender` — the same field
    // it has always lived on. No step after Profile For touches it, and none
    // of them may clear it: `user_profiles.gender` is NOT NULL and every
    // match query filters on it first.
    expect(container.read(registrationProvider).basicDetails.gender, 'Male');

    // And it reaches the backend on the same `updateBasicDetails` call that
    // has always carried it — Profile For itself sends nothing, because it
    // runs before any credential exists.
    expect(repository.savedBasic?.gender, 'Male');
    expect(repository.savedBasic?.toJson()['gender'], 'MALE');
  });

  test('the completed draft carries the profile columns onboarding collects',
      () async {
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    await completeOnboarding(container);
    final json = container.read(registrationProvider).toJson();

    final basic = json['basicDetails'] as Map<String, dynamic>;
    final religion = json['religionDetails'] as Map<String, dynamic>;
    final location = json['locationDetails'] as Map<String, dynamic>;

    for (final field in ['firstName', 'lastName', 'gender', 'maritalStatus',
      'dob']) {
      expect(basic[field], isNotNull, reason: 'basicDetails.$field');
      expect('${basic[field]}'.trim(), isNotEmpty, reason: 'basicDetails.$field');
    }
    expect(religion['religion'], 'Hindu');
    expect(location['state'], 'Tamil Nadu');
    expect(location['city'], 'Chennai');

    // The enum mapping the backend DTOs demand — 'Male'/'Never Married' are
    // the draft's display values and would both be rejected by class-validator.
    expect(basic['gender'], 'MALE');
    expect(basic['maritalStatus'], 'NEVER_MARRIED');
  });

  test('the serialized payload omits what onboarding does not collect, and '
      'sends no empty strings', () async {
    // The exact JSON that goes on the wire to
    // `PATCH /profiles/draft/{section}`. Two rules, both load-bearing:
    //
    //  1. Caste and mother tongue are absent, not `''`. Onboarding stopped
    //     asking; both columns are nullable as of migration 20260903120000,
    //     so absence stores as SQL NULL. An empty string would be a value the
    //     member never gave, and `mergeDraftSection` would persist it.
    //  2. NOTHING is an empty string. `toJson` omits empty fields section by
    //     section, which is what keeps an optional answer the member skipped
    //     from becoming meaningless data in `draft_data` and then in
    //     `user_profiles`.
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    await completeOnboarding(container);
    final json = container.read(registrationProvider).toJson();

    final religion = json['religionDetails'] as Map<String, dynamic>;
    expect(religion.containsKey('caste'), isFalse);
    final language = json['languageDetails'];
    expect(
      language == null || (language as Map).isEmpty,
      isTrue,
      reason: 'no onboarding step writes the language section any more',
    );

    // What the payload MUST carry, in the sections that own each value.
    expect((json['basicDetails'] as Map)['gender'], 'MALE');
    expect(religion['religion'], 'Hindu');
    expect((json['locationDetails'] as Map)['state'], 'Tamil Nadu');
    expect((json['locationDetails'] as Map)['city'], 'Chennai');

    // No empty string anywhere in the payload, at any depth.
    void assertNoEmptyStrings(Object? node, String path) {
      if (node is String) {
        expect(node, isNotEmpty, reason: '$path is an empty string');
      } else if (node is Map) {
        node.forEach((k, v) => assertNoEmptyStrings(v, '$path.$k'));
      } else if (node is List) {
        for (var i = 0; i < node.length; i++) {
          assertNoEmptyStrings(node[i], '$path[$i]');
        }
      }
    }

    assertNoEmptyStrings(json, 'draft');
  });

  test('an omitted optional answer is absent rather than blank', () async {
    // Sub-community is the optional field on the "Let's build your Profile"
    // step. Skipping it must leave `subCaste` out of the payload entirely —
    // sending `""` would overwrite a real value on the next merge.
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    final notifier = container.read(registrationProvider.notifier);
    notifier.applyProfileFor(
      const ProfileForForm(profileCreatedFor: 'Myself', gender: 'Male'),
    );
    await notifier.applyProfileBasics(
      const ProfileBasicsForm(state: 'Tamil Nadu', city: 'Chennai'),
    );

    final religion =
        container.read(registrationProvider).toJson()['religionDetails'];
    expect(
      religion == null || !(religion as Map).containsKey('subCaste'),
      isTrue,
      reason: 'an unanswered optional field is omitted, never sent as ""',
    );
  });

  test('every step reaches the backend, and none is left behind', () async {
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    await completeOnboarding(container);

    // The sections the profile write reads. Onboarding has no later
    // "Continue" that syncs these for it — a section missing here is a
    // section the backend never sees.
    expect(
      repository.savedSections.toSet(),
      containsAll(<String>[
        'basicDetails',
        'religionDetails',
        'locationDetails',
        'physicalDetails',
        'educationDetails',
        'lifestyleDetails',
      ]),
    );
  });

  test('going back to an earlier step does not reset the ones after it',
      () async {
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    await completeOnboarding(container);

    // Back to Profile For, changing the answer, and forward again. This is
    // the exact path that used to wipe the draft: CreateProfileForPage's
    // Continue called startCreateMode().
    final notifier = container.read(registrationProvider.notifier);
    notifier.enterCreateMode();
    notifier.applyProfileFor(
      const ProfileForForm(profileCreatedFor: 'Daughter', gender: 'Female'),
    );

    final draft = container.read(registrationProvider);
    expect(draft.basicDetails.profileCreatedFor, 'Daughter');
    // Re-answering step 1 rewrites both of its own fields and nothing else.
    expect(draft.basicDetails.gender, 'Female');
    expect(draft.basicDetails.firstName, 'Arjun');
    expect(draft.basicDetails.dob, DateTime(1998, 2, 5));
    expect(draft.religionDetails.religion, 'Hindu');
    expect(draft.locationDetails.city, 'Chennai');
    expect(draft.educationDetails.annualIncome, 'Rs. 10 - 15 Lakhs');
    expect(draft.lifestyleDetails.aboutMe, isNotEmpty);
  });

  test('a step whose save fails keeps its answers in the draft', () async {
    final container = containerWith(
      RecordingRegistrationRepository(failReligion: true),
    );
    addTearDown(container.dispose);

    final notifier = container.read(registrationProvider.notifier);
    await expectLater(
      notifier.applyOnboardingReligion(
        const OnboardingReligionForm(
          religion: 'Hindu',
          community: 'Vellalar',
          livingIn: 'India',
        ),
      ),
      throwsA(isA<Exception>()),
    );

    // The throw is what keeps the member on the screen (see
    // OnboardingStepScaffold._continue). It must not also cost them the
    // answers: local state is written before the network call, so a retry —
    // or the end-of-onboarding flush — still carries them.
    final draft = container.read(registrationProvider);
    expect(draft.religionDetails.religion, 'Hindu');
    expect(draft.religionDetails.community, 'Vellalar');
    expect(draft.locationDetails.country, 'India');
  });

  test('signed out, answers are held locally and nothing is sent', () async {
    // The common path: onboarding runs before any credential exists, so
    // every PATCH would be a guaranteed 401. Persisting locally instead is
    // what lets the flush at the OTP step carry the whole profile at once.
    final repository = RecordingRegistrationRepository();
    final container = ProviderContainer(
      overrides: [registrationRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    await completeOnboarding(container);

    expect(repository.savedSections, isEmpty);
    // ...but the draft is complete, which is what the flush then sends.
    final draft = container.read(registrationProvider);
    expect(draft.basicDetails.firstName, 'Arjun');
    expect(draft.locationDetails.city, 'Chennai');
    expect(draft.lifestyleDetails.aboutMe, isNotEmpty);
  });

  test('the end-of-onboarding flush sends the whole draft once a session '
      'exists', () async {
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    await completeOnboarding(container);
    repository.savedSections.clear();

    // What OnboardingVerifyMobilePage calls the moment the dummy OTP has been
    // exchanged for a real Firebase session.
    await container.read(registrationProvider.notifier)
        .flushOnboardingToBackend();

    expect(
      repository.savedSections,
      containsAll(<String>[
        'basicDetails',
        'religionDetails',
        'languageDetails',
        'locationDetails',
        'physicalDetails',
        'educationDetails',
        'lifestyleDetails',
      ]),
    );
    expect(repository.savedBasic?.firstName, 'Arjun');
    expect(repository.savedBasic?.dob, DateTime(1998, 2, 5));
    expect(repository.savedReligion?.subCaste, 'Iyer');
    expect(repository.savedLocation?.city, 'Chennai');
  });

  test('a resumed session picks the flow up where it stopped', () async {
    final container = containerWith(RecordingRegistrationRepository());
    addTearDown(container.dispose);

    // What SplashController and PostAuthDestination do with a draft read back
    // from disk or from `GET /profiles/draft`.
    container.read(registrationProvider.notifier).restore(
          ProfileDraft(
            basicDetails: BasicDetails(
              profileCreatedFor: 'Myself',
              gender: 'Female',
              firstName: 'Meera',
              lastName: 'Rajan',
              dob: DateTime(1995, 3, 21),
            ),
          ),
          ProfileFlowMode.create,
        );

    final draft = container.read(registrationProvider);
    expect(draft.basicDetails.firstName, 'Meera');
    // Two steps answered, so the next one owed is Religion — not the start.
    expect(
      OnboardingNameForm.fromDraft(
        firstName: draft.basicDetails.firstName,
        lastName: draft.basicDetails.lastName,
        dob: draft.basicDetails.dob,
      ).isComplete,
      isTrue,
    );
    expect(
      const OnboardingReligionForm().isComplete,
      isFalse,
      reason: 'Religion is the first unanswered step',
    );
  });

  test('a Google signup produces the same payload as any other method',
      () async {
    // Google supplies an identity, not a profile. Once the member has walked
    // the same onboarding every other signup method walks, the draft that
    // reaches the backend must be indistinguishable from a mobile or email
    // signup's — same sections, same fields, same enum mapping. A Google
    // shortcut anywhere in the flow would show up here as a missing field.
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    // What GoogleSignInController does for GoogleAuthIntent.signup before
    // routing: a clean CREATE-mode draft, then the ordinary flow.
    container.read(registrationProvider.notifier).startCreateMode();
    await completeOnboarding(container);
    await container.read(registrationProvider.notifier)
        .flushOnboardingToBackend();

    final basic = repository.savedBasic!.toJson();
    expect(basic['gender'], 'MALE');
    expect(basic['firstName'], 'Arjun');
    expect(basic['lastName'], 'Krishnan');
    expect(basic['maritalStatus'], 'NEVER_MARRIED');
    expect(basic['profileCreatedFor'], 'Myself');
    expect(repository.savedLocation?.city, 'Chennai');
    expect(
      repository.savedSections.toSet(),
      containsAll(<String>[
        'basicDetails',
        'religionDetails',
        'locationDetails',
        'physicalDetails',
        'educationDetails',
        'lifestyleDetails',
      ]),
    );
  });

  group('the onboarding route chain is linear and complete', () {
    test('every step is reachable without a session', () {
      // Onboarding runs signed out from Profile For to the OTP step. A step
      // missing from `publicRoutes` is a redirect to the landing screen
      // half-way through signup.
      for (final route in [
        RouteNames.createProfileFor,
        RouteNames.onboardingNameDob,
        RouteNames.onboardingReligion,
        RouteNames.onboardingContact,
        RouteNames.profileBasics,
        RouteNames.onboardingMarital,
        RouteNames.onboardingEducation,
        RouteNames.onboardingIncome,
        RouteNames.onboardingPhotos,
        RouteNames.onboardingAbout,
        RouteNames.onboardingVerifyMobile,
      ]) {
        expect(
          RouteNames.publicRoutes,
          contains(route),
          reason: '$route is an onboarding step and runs signed out',
        );
      }
    });

    test('Discover is not public', () {
      // The other half of the same rule: the destination signup ends at is
      // behind the guard, so nothing reaches it without a session.
      expect(RouteNames.publicRoutes, isNot(contains(RouteNames.discover)));
    });
  });
}
