import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/profile_draft.dart';

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
