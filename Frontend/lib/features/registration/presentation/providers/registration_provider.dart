import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../authentication/presentation/providers/auth_providers.dart';

import '../../../../core/network/api_providers.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../psychology/domain/models/personality_result.dart';
import '../../../psychology/presentation/providers/personality_provider.dart';
import '../../data/repositories/registration_repository.dart';
import '../../domain/models/onboarding_forms.dart';
import '../../domain/models/profile_draft.dart';
import '../../domain/models/profile_flow_mode.dart';

/// Wraps the shared [apiClientProvider] (Firebase-token-authenticated).
final registrationRepositoryProvider = Provider<RegistrationRepository>(
  (ref) => RegistrationRepository(ref.watch(apiClientProvider)),
);

/// Whether the wizard/review screens are being used to create a brand-new
/// profile (fresh signup) or to edit an existing, already-finalized one
/// (opened from the navigation drawer). Same screens, different save
/// destinations — see [RegistrationNotifier.startCreateMode] /
/// [RegistrationNotifier.startEditMode].
final profileFlowModeProvider =
    StateProvider<ProfileFlowMode>((ref) => ProfileFlowMode.create);

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
  // step's data was just filled in. Step 9 (psychological quiz) is synced
  // independently by the psychology feature's own repository the moment
  // the quiz is submitted, not through this draft. Step 10 (partner
  // preference) is a CTA card that pushes the standalone Partner
  // Preferences page, which already persists immediately via
  // [savePartnerPreference] when the user saves there — nothing left to
  // sync here. Steps 11 (photos) and 12 (verification) aren't sent here
  // either: photos persist immediately via PhotoController on upload, and
  // verification status is read-only, reflecting other modules.
  // [skipMaterialize] — set by ProfileWizardPage's edit-mode save
  // (_saveAndFinalizeForEdit), which always calls finalizeToBackend()
  // immediately after this. finalize() unconditionally redoes the same
  // materialize-and-recompute work this step-save would otherwise trigger
  // server-side (see ProfileDraftController.save's skipMaterialize doc), so
  // without this flag every edit-mode "Continue" tap paid for that work
  // twice — measured ~1.8s of pure duplication on top of finalize()'s own
  // ~3s. CREATE mode never sets this; it never calls finalize per step, so
  // this auto-materialize is the only thing that makes a user matchable
  // before they reach Profile Review.
  Future<void> syncCurrentStepToBackend({bool skipMaterialize = false}) async {
    final repo = ref.read(registrationRepositoryProvider);
    switch (state.currentStep) {
      case 0:
        await repo.updateBasicDetails(state.basicDetails,
            skipMaterialize: skipMaterialize);
        return;
      case 1:
        await repo.updateReligionDetails(state.religionDetails,
            skipMaterialize: skipMaterialize);
        return;
      case 2:
        await repo.updateLanguageDetails(state.languageDetails,
            skipMaterialize: skipMaterialize);
        return;
      case 3:
        await repo.updateLocationDetails(state.locationDetails,
            skipMaterialize: skipMaterialize);
        return;
      case 4:
        await repo.updateEducationDetails(state.educationDetails,
            skipMaterialize: skipMaterialize);
        return;
      case 5:
        await repo.updatePhysicalDetails(state.physicalDetails,
            skipMaterialize: skipMaterialize);
        return;
      case 6:
        await repo.updateLifestyleDetails(state.lifestyleDetails,
            skipMaterialize: skipMaterialize);
        return;
      case 7:
        await repo.updateFamilyDetails(state.familyDetails,
            skipMaterialize: skipMaterialize);
        return;
      case 8:
        await repo.updateHoroscopeDetails(state.horoscopeDetails,
            skipMaterialize: skipMaterialize);
        return;
      default:
        // Steps 9 (psychological quiz), 10 (partner preference), 11
        // (photos), 12 (verification): nothing to sync here.
        return;
    }
  }

  /// Maps the accumulated draft into the finalized backend profile. Call
  /// from the Profile Review screen's "Enter App" button. Idempotent on the
  /// backend, so this also doubles as the EDIT MODE "publish my changes"
  /// step — see [startEditMode].
  Future<void> finalizeToBackend() async {
    await ref.read(registrationRepositoryProvider).finalizeProfile();
    // finalize() recomputes completion and materializes photos/astrology
    // server-side, so any Profile read before this call is stale. Both the
    // registration success screen and ProfilePage read myProfileProvider —
    // without this, an EDIT session that had already opened ProfilePage
    // would serve the pre-edit cached profile. (myProfileProvider's own doc
    // comment has always claimed this invalidation happened; it did not.)
    ref.invalidate(myProfileProvider);
  }

  // ─── Flow Mode ───────────────────────────────────────────────────────
  //
  // CREATE and EDIT reuse this exact wizard/review UI — only the mode flag
  // and where the draft data comes from differ.

  /// Switches to CREATE mode with an empty draft — the normal first-time
  /// signup path. Also used to reset state after an EDIT session ends.
  void startCreateMode() {
    ref.read(profileFlowModeProvider.notifier).state = ProfileFlowMode.create;
    state = const ProfileDraft();
  }

  /// Switches to EDIT mode and hydrates the draft from the logged-in
  /// user's saved data (`GET /profiles/draft`) — called before opening
  /// Edit Profile / Verification Center from the navigation drawer, so
  /// those screens open pre-populated with the user's existing values.
  Future<void> startEditMode() async {
    final json = await ref.read(registrationRepositoryProvider).getDraft();
    ref.read(profileFlowModeProvider.notifier).state = ProfileFlowMode.edit;
    state = ProfileDraft.fromJson(json).copyWith(currentStep: 0);
  }

  /// Sets an exact draft + mode combination directly, with no network call
  /// or reset. Used only by [SplashController] to resume a mid-registration
  /// or mid-edit session that survived an app-process restart (see
  /// StorageService.saveNavState / AppLifecycleObserver).
  void restore(ProfileDraft draft, ProfileFlowMode mode) {
    ref.read(profileFlowModeProvider.notifier).state = mode;
    state = draft;
  }

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

  // ─── Onboarding persistence ────────────────────────────────────────
  //
  // Onboarding now runs before there is an account: the landing page's
  // sign-up buttons go straight to Profile For, and credentials are
  // collected part-way through (Email + Mobile) rather than up front. So a
  // step cannot assume a Firebase session — a PATCH sent without one is a
  // guaranteed 401, which would strand the member on a screen they have
  // correctly filled in.
  //
  // Every answer is therefore written to the local draft first and snapshot
  // to disk, so nothing is lost and a relaunch resumes where they stopped.
  // The backend copy is brought up to date the moment a session exists —
  // see [flushOnboardingToBackend].

  /// Whether a Firebase session exists. Guarded: reading the auth service
  /// before Firebase is initialised (a widget test, a very early call)
  /// throws, and "cannot tell" must mean "persist locally", never a crash
  /// that strands the member on a completed screen.
  bool get _hasSession {
    try {
      return ref.read(firebaseAuthServiceProvider).currentUser != null;
    } catch (_) {
      return false;
    }
  }

  /// Snapshots the draft locally. Cheap, and the only persistence available
  /// while signed out.
  Future<void> _snapshot() async {
    // Best-effort: local storage may not be initialised (widget tests), and
    // a snapshot failing must not fail the step the member just completed —
    // the in-memory draft is still correct either way.
    try {
      await storageService.saveNavState(
        route: RouteNames.createProfileFor,
        profileFlowMode: ProfileFlowMode.create.name,
        profileDraftJson: jsonEncode(state.toJson()),
      );
    } catch (_) {}
  }

  /// Runs [send] only when there is a session to authenticate it. Signed
  /// out, the local snapshot above is the whole of persistence and this is
  /// a no-op rather than a failure.
  Future<void> _persist(Future<void> Function() send) async {
    await _snapshot();
    if (!_hasSession) return;
    await send();
  }

  /// Step 3 — "Email + Mobile". Captured only; nothing is verified here and
  /// no Phone Auth call is made. Both values live on the Firebase account
  /// rather than the profile draft, so with no session yet they are held
  /// locally until [flushOnboardingToBackend] has somewhere to send them.
  Future<void> applyOnboardingContact({
    required String email,
    required String phoneE164,
  }) async {
    // Best-effort, like the draft snapshot: local storage may be
    // unavailable, and losing a prefill must not fail a step the member has
    // correctly completed.
    try {
      await storageService.setPendingEmail(email);
      await storageService.setPendingPhone(phoneE164);
    } catch (_) {}
    await _snapshot();
  }

  /// Pushes every onboarding answer the draft holds to the backend. Called
  /// once a session exists — after the Email + Mobile step links an account,
  /// and again at the end of onboarding — so the work done while signed out
  /// is not stranded on the device.
  ///
  /// Best-effort and never throws: the local draft remains the source of
  /// truth until a call succeeds, and the next step's save retries anyway.
  Future<void> flushOnboardingToBackend() async {
    if (!_hasSession) return;
    final repo = ref.read(registrationRepositoryProvider);
    try {
      await repo.updateBasicDetails(state.basicDetails);
      await repo.updateReligionDetails(state.religionDetails);
      await repo.updateLocationDetails(state.locationDetails);
      await repo.updatePhysicalDetails(state.physicalDetails);
      await repo.updateEducationDetails(state.educationDetails);
      await repo.updateLifestyleDetails(state.lifestyleDetails);
    } catch (_) {
      // Left for the next successful save to carry.
    }
  }

  // ─── Onboarding steps ──────────────────────────────────────────────
  //
  // Onboarding writes into the sections the profile already owns rather
  // than a section of its own — religion/community onto Religion, and
  // country/state/city onto Location — so Edit Profile reopens those
  // screens pre-filled and the existing per-section PATCH carries the
  // values to the backend. That mapping is why these live here and not in
  // the pages: a page knows the answers it collected, not which sections
  // they belong to.
  //
  // Both persist immediately. Onboarding is not the wizard: there is no
  // later "Continue" that will sync the section for them, and a member goes
  // straight to Discover at the end, so anything left only in local state
  // would be lost on the next cold start.

  /// Step 2 — "Your religion". Writes religion + community, the country the
  /// member lives in, and (when ticked) the partner-community preference.
  Future<void> applyOnboardingReligion(OnboardingReligionForm form) async {
    state = state.copyWith(
      religionDetails: state.religionDetails.copyWith(
        religion: form.religion,
        community: form.community,
      ),
      locationDetails: state.locationDetails.copyWith(country: form.livingIn),
    );

    await _persist(() async {
      final repo = ref.read(registrationRepositoryProvider);
      await repo.updateReligionDetails(state.religionDetails);
      await repo.updateLocationDetails(state.locationDetails);
    });

    // Partner preference has no per-section sync of its own during
    // onboarding, so the flag goes through the same call the standalone
    // Partner Preferences page uses.
    final castePref =
        form.casteNoBar ? OnboardingReligionForm.casteNoBarPreference : '';
    if (castePref == state.partnerPreference.castePref) return;
    state = state.copyWith(
      partnerPreference:
          state.partnerPreference.copyWith(castePref: castePref),
    );
    await _persist(
      () => ref
          .read(registrationRepositoryProvider)
          .updatePartnerPreference(state.partnerPreference),
    );
  }

  /// Step 4 — "State & City".
  Future<void> applyProfileBasics(ProfileBasicsForm form) async {
    state = state.copyWith(
      locationDetails: state.locationDetails.copyWith(
        state: form.state,
        city: form.city,
      ),
    );
    await _persist(
      () => ref
          .read(registrationRepositoryProvider)
          .updateLocationDetails(state.locationDetails),
    );
  }

  /// Step 5 — "Marital status", which also carries height and diet. Three
  /// sections, so three PATCHes: the backend has no combined endpoint and
  /// inventing one for onboarding would duplicate what already works.
  Future<void> applyOnboardingMarital(OnboardingMaritalForm form) async {
    state = state.copyWith(
      basicDetails:
          state.basicDetails.copyWith(maritalStatus: form.maritalStatus),
      physicalDetails: state.physicalDetails.copyWith(height: form.height),
      lifestyleDetails:
          state.lifestyleDetails.copyWith(eatingHabit: form.diet),
    );
    await _persist(() async {
      final repo = ref.read(registrationRepositoryProvider);
      await repo.updateBasicDetails(state.basicDetails);
      await repo.updatePhysicalDetails(state.physicalDetails);
      if (form.diet.trim().isNotEmpty) {
        await repo.updateLifestyleDetails(state.lifestyleDetails);
      }
    });
  }

  /// Step 6 — "Highest qualification".
  Future<void> applyOnboardingEducation(OnboardingEducationForm form) async {
    state = state.copyWith(
      educationDetails: state.educationDetails.copyWith(
        qualification: form.qualification,
        college: form.college,
      ),
    );
    await _persist(
      () => ref
          .read(registrationRepositoryProvider)
          .updateEducationDetails(state.educationDetails),
    );
  }

  /// Step 7 — "Annual income" and work details. Same draft section as step 6,
  /// so this PATCHes the whole of it again with both steps' answers merged.
  Future<void> applyOnboardingIncome(OnboardingIncomeForm form) async {
    state = state.copyWith(
      educationDetails: state.educationDetails.copyWith(
        annualIncome: form.annualIncome,
        employmentType: form.workWith,
        occupation: form.workAs,
        company: form.companyName,
      ),
    );
    await _persist(
      () => ref
          .read(registrationRepositoryProvider)
          .updateEducationDetails(state.educationDetails),
    );
  }

  /// Step 9 — "About yourself".
  Future<void> applyOnboardingAbout(String aboutMe) async {
    state = state.copyWith(
      lifestyleDetails: state.lifestyleDetails.copyWith(aboutMe: aboutMe),
    );
    await _persist(
      () => ref
          .read(registrationRepositoryProvider)
          .updateLifestyleDetails(state.lifestyleDetails),
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

  // ─── Step 10: Psychological Quiz (read-only, on demand) ──────────────
  //
  // No answers/scores/completion flag are ever mirrored into ProfileDraft
  // — the psychology feature (PersonalityRepository) is the single source
  // of truth. When registration flow logic needs to know step-10 status
  // (e.g. finalize-time checks), it pulls straight from there instead of
  // maintaining a synchronized copy. StepPsychologicalQuiz itself never
  // calls this — it displays status by watching
  // myPersonalityResultProvider directly, the same as everywhere else.
  Future<PersonalityResult?> psychologyQuizResult() {
    return ref.read(personalityRepositoryProvider).getMyResult();
  }

  // ─── Step 11: Partner Preference ───────────────────────────────────
  //
  // No wizard-local update-only method — the in-wizard step is now just a
  // CTA card (see PartnerPreferenceStepCard) that pushes the standalone
  // Partner Preferences page, which edits and persists in one step via
  // [savePartnerPreference] below.

  /// Updates local state AND persists immediately — used by the standalone
  /// Partner Preferences page (features/partner_preferences), which isn't
  /// part of the step-by-step wizard flow and so can't rely on
  /// [syncCurrentStepToBackend]'s step-index switch. Same repository call
  /// that switch makes for step 10.
  Future<void> savePartnerPreference(PartnerPreference details) async {
    state = state.copyWith(partnerPreference: details);
    await ref.read(registrationRepositoryProvider).updatePartnerPreference(details);
  }

  // ─── Step 12: Photos ───────────────────────────────────────────────
  void updatePhotoGallery(PhotoGallery gallery) {
    state = state.copyWith(photoGallery: gallery);
  }

  // ─── Step 13: Verification ─────────────────────────────────────────
  void updateVerificationStatus(VerificationStatus status) {
    state = state.copyWith(verificationStatus: status);
  }

  // ─── Reset ─────────────────────────────────────────────────────────
  void reset() {
    state = const ProfileDraft();
  }
}
