import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// Editing a profile: **each section is saved on its own, by its own
/// `PATCH /profiles/draft/<section>`, and nothing else is sent.**
///
/// Edit Profile used to be one page with one Save that republished every
/// section of the draft, so changing a city also re-sent the member's basic
/// details, religion, education and the rest — any of which a stale copy
/// could overwrite. Each section now has an edit page of its own, and its
/// Save calls exactly one of these methods.
///
/// Editing is also not completing a registration: none of these call
/// `POST /profiles/finalize`, whose end-of-signup gate rejects the optional
/// sections onboarding half-fills on the member's behalf.
void main() {
  final saved = ProfileDraft(
    basicDetails: BasicDetails(
      firstName: 'Meera',
      lastName: 'Rajan',
      gender: 'Female',
      dob: DateTime(1995, 3, 21),
      profileCreatedFor: 'Myself',
    ),
    locationDetails: const LocationDetails(
      country: 'India',
      state: 'Tamil Nadu',
      city: 'Chennai',
    ),
  );

  ProviderContainer editing(RecordingRegistrationRepository repository) {
    final container = ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(repository),
        firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
      ],
    );
    container
        .read(registrationProvider.notifier)
        .restore(saved, ProfileFlowMode.edit);
    return container;
  }

  /// Every section save: its name on the wire, the call, and how to read the
  /// section back off the draft.
  final sections =
      <
        String,
        (
          Future<void> Function(RegistrationNotifier),
          Object Function(ProfileDraft),
        )
      >{
        'basicDetails': (
          (n) => n.publishBasicDetails(const BasicDetails(firstName: 'Anu')),
          (d) => d.basicDetails.firstName,
        ),
        'religionDetails': (
          (n) => n.publishReligionDetails(
            const ReligionDetails(religion: 'Hindu'),
          ),
          (d) => d.religionDetails.religion,
        ),
        'locationDetails': (
          (n) =>
              n.publishLocationDetails(const LocationDetails(city: 'Madurai')),
          (d) => d.locationDetails.city,
        ),
        'educationDetails': (
          (n) => n.publishEducationDetails(
            const EducationDetails(qualification: 'B.E.'),
          ),
          (d) => d.educationDetails.qualification,
        ),
        'physicalDetails': (
          (n) =>
              n.publishPhysicalDetails(const PhysicalDetails(height: "5'4\"")),
          (d) => d.physicalDetails.height,
        ),
        'lifestyleDetails': (
          (n) => n.publishLifestyleDetails(
            const LifestyleDetails(eatingHabit: 'Vegetarian'),
          ),
          (d) => d.lifestyleDetails.eatingHabit,
        ),
        'familyDetails': (
          (n) => n.publishFamilyDetails(
            const FamilyDetails(familyType: 'Nuclear'),
          ),
          (d) => d.familyDetails.familyType,
        ),
        'horoscopeDetails': (
          (n) =>
              n.publishHoroscopeDetails(const HoroscopeDetails(rashi: 'Mesha')),
          (d) => d.horoscopeDetails.rashi,
        ),
      };

  const expectedValues = {
    'basicDetails': 'Anu',
    'religionDetails': 'Hindu',
    'locationDetails': 'Madurai',
    'educationDetails': 'B.E.',
    'physicalDetails': "5'4\"",
    'lifestyleDetails': 'Vegetarian',
    'familyDetails': 'Nuclear',
    'horoscopeDetails': 'Mesha',
  };

  group('saving one section', () {
    for (final entry in sections.entries) {
      test(
        '${entry.key}: sends only that section, once, materializing',
        () async {
          final repository = RecordingRegistrationRepository();
          final container = editing(repository);
          addTearDown(container.dispose);

          await entry.value.$1(container.read(registrationProvider.notifier));

          expect(repository.savedSections, [entry.key]);
          // The only call, so it is the one that materializes.
          expect(repository.skipMaterializeFlags, [false]);
          expect(repository.finalizeCalls, 0);
          // Committed to the draft, so Edit Profile's summary shows it.
          expect(
            entry.value.$2(container.read(registrationProvider)),
            expectedValues[entry.key],
          );
        },
      );
    }
  });

  group('a failed save', () {
    test(
      'surfaces to the page and leaves the draft as the backend has it',
      () async {
        final container = editing(_FailingRepository());
        addTearDown(container.dispose);

        await expectLater(
          container
              .read(registrationProvider.notifier)
              .publishLocationDetails(const LocationDetails(city: 'Madurai')),
          throwsException,
        );
        // Not committed: the summary must not show a value that was not saved.
        expect(
          container.read(registrationProvider).locationDetails.city,
          'Chennai',
        );
      },
    );
  });

  test('there is no whole-profile save', () {
    // A structural check: one method that re-sent every section is exactly
    // what let one section's save overwrite another's.
    final provider = File(
      'lib/features/registration/presentation/providers/registration_provider.dart',
    ).readAsStringSync();
    expect(provider, isNot(contains('publishEditedProfile')));
  });
}

class _FailingRepository extends RecordingRegistrationRepository {
  @override
  Future<void> updateLocationDetails(
    LocationDetails details, {
    bool skipMaterialize = false,
  }) async {
    throw Exception('save failed');
  }
}
