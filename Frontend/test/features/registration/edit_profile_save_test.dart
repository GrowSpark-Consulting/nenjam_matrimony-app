import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nenjam_matrimony/features/authentication/presentation/providers/auth_providers.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_draft.dart';
import 'package:nenjam_matrimony/features/registration/domain/models/profile_flow_mode.dart';
import 'package:nenjam_matrimony/features/registration/presentation/providers/registration_provider.dart';

import 'onboarding_test_support.dart';

/// Editing a profile: **the section PATCH is the save, and it is not gated on
/// `POST /profiles/finalize`.**
///
/// Edit Profile used to save the open section and then call finalize, which
/// re-runs the end-of-*registration* gate. That gate rejects a half-filled
/// optional section — and onboarding half-fills three of them on the member's
/// behalf (height without weight; eatingHabit + aboutMe without
/// smoking/drinking/fitness/hobbies; every education field but workLocation).
/// So finalize answered 400 for every member who had signed up through
/// onboarding, naming sections they had never opened, and the screen reported
/// "could not save changes" over edits the PATCH had already written: the data
/// was saved, only the verdict was wrong.
///
/// Nothing about the finalize contract or its validation changed — CREATE mode
/// still calls it. These pin that editing no longer does.
void main() {
  ProviderContainer editing(RecordingRegistrationRepository repository) {
    final container = ProviderContainer(
      overrides: [
        registrationRepositoryProvider.overrideWithValue(repository),
        firebaseAuthServiceProvider.overrideWithValue(SignedInAuthService()),
      ],
    );
    container.read(registrationProvider.notifier).restore(
          ProfileDraft(
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
          ),
          ProfileFlowMode.edit,
        );
    return container;
  }

  // The per-section save (goToStep + publishEditedSection) was removed along
  // with the per-section wizard that drove it; Edit Profile is one scrolling
  // page whose Save goes through publishEditedProfile. The group that covered
  // it went with it — what it pinned (a section save must not be gated on
  // finalize) is still pinned below, on the path that is actually live.

  group('saving the whole profile from the review summary', () {
    test('republishes every section and materializes exactly once', () async {
      final repository = RecordingRegistrationRepository();
      final container = editing(repository);
      addTearDown(container.dispose);

      await container.read(registrationProvider.notifier).publishEditedProfile();

      expect(
        repository.savedSections,
        containsAll(<String>[
          'basicDetails',
          'religionDetails',
          'languageDetails',
          'locationDetails',
          'physicalDetails',
          'educationDetails',
          // Family and horoscope were absent from publishEditedProfile()
          // until Edit Profile became a single editable page. It never
          // showed, because the only way to reach those two sections was the
          // per-section wizard, which saved through publishEditedSection()
          // instead. Now that one Save covers every section at once, leaving
          // them out would silently drop the member's edits.
          'familyDetails',
          'horoscopeDetails',
          'lifestyleDetails',
        ]),
      );
      expect(repository.finalizeCalls, 0);
      // One materializing call, and it is the last — every section is stored
      // by then, so that single pass sees the whole draft.
      expect(
        repository.skipMaterializeFlags.where((skipped) => !skipped).length,
        1,
      );
      expect(repository.skipMaterializeFlags.last, isFalse);
    });

    test('a failure part-way through surfaces to the screen', () async {
      final repository = _FailingRepository();
      final container = editing(repository);
      addTearDown(container.dispose);

      await expectLater(
        container.read(registrationProvider.notifier).publishEditedProfile(),
        throwsException,
      );
    });
  });
}

class _FailingRepository extends RecordingRegistrationRepository {
  @override
  Future<void> updateBasicDetails(
    BasicDetails details, {
    bool skipMaterialize = false,
  }) async {
    throw Exception('save failed');
  }
}
