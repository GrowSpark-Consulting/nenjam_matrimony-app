import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// [RegistrationNotifier.flushOnboardingToBackend] — the single call that
/// carries a phone-signup member's answers to the backend.
///
/// That path has no Firebase session until the OTP step at the very end
/// mints one, so `_persist` no-ops for all nine preceding steps and this
/// flush is the only thing that ever reaches the API. Whatever it omits is
/// not "sent later" — it is never sent at all.
///
/// It omitted `languageDetails`. `motherTongue` is a NOT NULL column on
/// `user_profiles`, so the backend could not materialize a profile row:
/// verified against the live API with a fresh account, `GET /profiles/me`
/// answered 404 after a complete onboarding run and the member reached
/// Discover with no profile of their own.
void main() {
  ProviderContainer containerWith(RecordingRegistrationRepository repository) {
    return ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(repository),
        // The flush is a no-op without a session — the very condition that
        // makes it the only sender on the phone-signup path.
        firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
      ],
    );
  }

  /// A draft in the state onboarding leaves it in by the OTP step: every
  /// answer collected locally, nothing sent yet.
  ProfileDraft onboardedDraft() => const ProfileDraft().copyWith(
        basicDetails: const BasicDetails(
          firstName: 'Arjun',
          lastName: 'Krishnan',
          gender: 'Male',
          maritalStatus: 'Never Married',
          profileCreatedFor: 'Myself',
        ),
        religionDetails: const ReligionDetails(
          religion: 'Hindu',
          caste: 'Vanniyar',
          community: 'Tamil',
        ),
        languageDetails: const LanguageDetails(motherTongue: 'Tamil'),
        locationDetails: const LocationDetails(
          country: 'India',
          state: 'Tamil Nadu',
          city: 'Chennai',
        ),
      );

  test('the end-of-onboarding flush sends the mother tongue', () async {
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    final notifier = container.read(registrationProvider.notifier);
    notifier.restore(onboardedDraft(), ProfileFlowMode.create);

    await notifier.flushOnboardingToBackend();

    expect(
      repository.savedSections,
      contains('languageDetails'),
      reason: 'motherTongue is NOT NULL on user_profiles — without this '
          'section the backend cannot write a profile row at all, and the '
          'member lands on Discover with GET /profiles/me answering 404.',
    );
    expect(repository.savedLanguage?.motherTongue, 'Tamil');
  });

  test('the flush carries every section the profile row requires', () async {
    final repository = RecordingRegistrationRepository();
    final container = containerWith(repository);
    addTearDown(container.dispose);

    final notifier = container.read(registrationProvider.notifier);
    notifier.restore(onboardedDraft(), ProfileFlowMode.create);

    await notifier.flushOnboardingToBackend();

    // The four sections holding a NOT NULL column: names/gender/dob/marital
    // status, religion + caste, mother tongue, and state + city.
    expect(
      repository.savedSections,
      containsAll(<String>[
        'basicDetails',
        'religionDetails',
        'languageDetails',
        'locationDetails',
      ]),
    );
    expect(repository.savedBasic?.firstName, 'Arjun');
    expect(repository.savedReligion?.caste, 'Vanniyar');
    expect(repository.savedLocation?.city, 'Chennai');
  });

  test('signed out, the flush sends nothing', () async {
    final repository = RecordingRegistrationRepository();
    // No firebaseAuthServiceProvider override — no session.
    final container = ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(registrationProvider.notifier);
    notifier.restore(onboardedDraft(), ProfileFlowMode.create);

    await notifier.flushOnboardingToBackend();

    expect(repository.savedSections, isEmpty);
  });
}
