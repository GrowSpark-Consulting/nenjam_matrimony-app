import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/repositories/registration_repository.dart';
import '../../domain/models/profile_draft.dart';

/// Wraps the shared [apiClientProvider] (Firebase-token-authenticated).
final registrationRepositoryProvider = Provider<RegistrationRepository>(
  (ref) => RegistrationRepository(ref.watch(apiClientProvider)),
);

/// Riverpod provider for the registration wizard state.
///
/// Uses keepAlive so the wizard state persists across navigation
/// (e.g., going to Login and back) until explicitly reset.
final registrationProvider =
    NotifierProvider<RegistrationNotifier, ProfileDraft>(
  RegistrationNotifier.new,
);

class RegistrationNotifier extends Notifier<ProfileDraft> {
  @override
  ProfileDraft build() => const ProfileDraft();

  // ─── Backend sync ────────────────────────────────────────────────────
  //
  // Called from ProfileWizardPage's "Continue" button — sends whichever
  // step's data was just filled in. Steps 10 (photos) and 11 (verification)
  // aren't sent here: photo upload isn't wired to S3 yet, and verification
  // status is read-only, reflecting other modules.
  Future<void> syncCurrentStepToBackend() async {
    final repo = ref.read(registrationRepositoryProvider);
    switch (state.currentStep) {
      case 0:
        await repo.updateBasicDetails(state.basicDetails);
        return;
      case 1:
        await repo.updateReligionDetails(state.religionDetails);
        return;
      case 2:
        await repo.updateLanguageDetails(state.languageDetails);
        return;
      case 3:
        await repo.updateLocationDetails(state.locationDetails);
        return;
      case 4:
        await repo.updateEducationDetails(state.educationDetails);
        return;
      case 5:
        await repo.updatePhysicalDetails(state.physicalDetails);
        return;
      case 6:
        await repo.updateLifestyleDetails(state.lifestyleDetails);
        return;
      case 7:
        await repo.updateFamilyDetails(state.familyDetails);
        return;
      case 8:
        await repo.updateHoroscopeDetails(state.horoscopeDetails);
        return;
      case 9:
        await repo.updatePartnerPreference(state.partnerPreference);
        return;
      default:
        // Steps 10-11: nothing to sync.
        return;
    }
  }

  /// Maps the accumulated draft into the finalized backend profile. Call
  /// from the Profile Review screen's "Enter App" button.
  Future<void> finalizeToBackend() =>
      ref.read(registrationRepositoryProvider).finalizeProfile();

  // ─── Step Navigation ───────────────────────────────────────────────
  void goToStep(int step) {
    if (step >= 0 && step < ProfileDraft.totalSteps) {
      state = state.copyWith(currentStep: step);
    }
  }

  void nextStep() {
    if (state.currentStep < ProfileDraft.totalSteps - 1) {
      state = state.copyWith(currentStep: state.currentStep + 1);
    }
  }

  void previousStep() {
    if (state.currentStep > 0) {
      state = state.copyWith(currentStep: state.currentStep - 1);
    }
  }

  // ─── Profile Created For ───────────────────────────────────────────
  void setProfileCreatedFor(String value) {
    state = state.copyWith(
      basicDetails: state.basicDetails.copyWith(profileCreatedFor: value),
    );
  }

  // ─── Step 1: Basic Details ─────────────────────────────────────────
  void updateBasicDetails(BasicDetails details) {
    state = state.copyWith(basicDetails: details);
  }

  // ─── Step 2: Religion ──────────────────────────────────────────────
  void updateReligionDetails(ReligionDetails details) {
    state = state.copyWith(religionDetails: details);
  }

  // ─── Step 3: Language ──────────────────────────────────────────────
  void updateLanguageDetails(LanguageDetails details) {
    state = state.copyWith(languageDetails: details);
  }

  // ─── Step 4: Location ──────────────────────────────────────────────
  void updateLocationDetails(LocationDetails details) {
    state = state.copyWith(locationDetails: details);
  }

  // ─── Step 5: Education ─────────────────────────────────────────────
  void updateEducationDetails(EducationDetails details) {
    state = state.copyWith(educationDetails: details);
  }

  // ─── Step 6: Physical ──────────────────────────────────────────────
  void updatePhysicalDetails(PhysicalDetails details) {
    state = state.copyWith(physicalDetails: details);
  }

  // ─── Step 7: Lifestyle ─────────────────────────────────────────────
  void updateLifestyleDetails(LifestyleDetails details) {
    state = state.copyWith(lifestyleDetails: details);
  }

  // ─── Step 8: Family ────────────────────────────────────────────────
  void updateFamilyDetails(FamilyDetails details) {
    state = state.copyWith(familyDetails: details);
  }

  // ─── Step 9: Horoscope ─────────────────────────────────────────────
  void updateHoroscopeDetails(HoroscopeDetails details) {
    state = state.copyWith(horoscopeDetails: details);
  }

  // ─── Step 10: Partner Preference ───────────────────────────────────
  void updatePartnerPreference(PartnerPreference details) {
    state = state.copyWith(partnerPreference: details);
  }

  // ─── Step 11: Photos ───────────────────────────────────────────────
  void updatePhotoGallery(PhotoGallery gallery) {
    state = state.copyWith(photoGallery: gallery);
  }

  // ─── Step 12: Verification ─────────────────────────────────────────
  void updateVerificationStatus(VerificationStatus status) {
    state = state.copyWith(verificationStatus: status);
  }

  // ─── Reset ─────────────────────────────────────────────────────────
  void reset() {
    state = const ProfileDraft();
  }
}
