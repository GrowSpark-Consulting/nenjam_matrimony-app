import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';
import '../../../authentication/domain/services/local_auth_session.dart';
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
  // Sends whichever single section [ProfileDraft.currentStep] names, via
  // [publishEditedSection]. Step 9 (psychological quiz) is synced
  // independently by the psychology feature's own repository the moment
  // the quiz is submitted, not through this draft. Step 10 (partner
  // preference) is handled by the standalone Partner Preferences page,
  // which already persists immediately via [savePartnerPreference] when
  // the user saves there — nothing left to sync here. Steps 11 (photos)
  // and 12 (verification) aren't sent here either: photos persist
  // immediately via PhotoController on upload, and verification status is
  // read-only, reflecting other modules.
  //
  // [skipMaterialize] suppresses the server-side materialize-and-recompute
  // pass this save would otherwise trigger (see
  // ProfileDraftController.save's skipMaterialize doc) — for a caller that
  // writes several sections in a row and materializes once at the end
  // instead of paying for that work on every one. [publishEditedProfile]
  // is the shape that needs it; a lone section save leaves it off, because
  // nothing follows it to do that work.
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
  /// EDIT MODE's save. Writes the sections the member changed and leaves
  /// them materialized — without asking `POST /profiles/finalize` whether
  /// the *registration* is complete.
  ///
  /// That question is why editing used to fail. finalize() re-runs the
  /// end-of-signup gate, which rejects a half-filled optional section — and
  /// onboarding half-fills three of them on the member's behalf: it stores
  /// `height` but never `weight`, `eatingHabit` + `aboutMe` but never
  /// smoking/drinking/fitness/hobbies, and every education field but
  /// `workLocation`. So finalize answered 400 for every member who signed up
  /// through onboarding, naming sections they had never opened, and Edit
  /// Profile reported "could not save changes" — over edits the PATCH above
  /// had in fact already written. The data was saved; only the verdict was
  /// wrong.
  ///
  /// Editing an existing profile is not completing a registration, so it no
  /// longer asks that question. The section PATCH is the save: it stores the
  /// values and, with materialization on, rewrites `user_profiles` and
  /// recomputes completion server-side — everything an edit needs. Nothing
  /// about the finalize contract or its validation changed; CREATE mode still
  /// calls it, unchanged, from the Completing screen.
  Future<void> publishEditedSection() async {
    await syncCurrentStepToBackend();
    ref.invalidate(myProfileProvider);
  }

  /// EDIT MODE's "Save Changes" from the review summary, where there is no
  /// single open section to save: republishes the whole draft, materializing
  /// once at the end. The same order and the same one-materialization rule
  /// [flushOnboardingToBackend] uses — but errors propagate, because this one
  /// is a member pressing Save and being told whether it worked.
  Future<void> publishEditedProfile() async {
    final repo = ref.read(registrationRepositoryProvider);
    await repo.updateBasicDetails(state.basicDetails, skipMaterialize: true);
    await repo.updateReligionDetails(state.religionDetails,
        skipMaterialize: true);
    await repo.updateLanguageDetails(state.languageDetails,
        skipMaterialize: true);
    await repo.updateLocationDetails(state.locationDetails,
        skipMaterialize: true);
    await repo.updatePhysicalDetails(state.physicalDetails,
        skipMaterialize: true);
    await repo.updateEducationDetails(state.educationDetails,
        skipMaterialize: true);
    // Family and horoscope were missing here until Edit Profile became a
    // single editable page. It never showed, because the only way to reach
    // those two sections was the per-section wizard, which saved through
    // publishEditedSection() instead. Now that one Save covers every section
    // at once, leaving them out would silently drop the member's edits.
    await repo.updateFamilyDetails(state.familyDetails, skipMaterialize: true);
    await repo.updateHoroscopeDetails(state.horoscopeDetails,
        skipMaterialize: true);
    // Last, and the only one that materializes — see flushOnboardingToBackend.
    await repo.updateLifestyleDetails(state.lifestyleDetails);
    ref.invalidate(myProfileProvider);
  }

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

  /// Finalizes the registration at the end of onboarding, swallowing any
  /// failure.
  ///
  /// Same call as [finalizeToBackend]; the difference is who it is for. The
  /// wizard's Review screen shows the member a spinner and can report an error
  /// they can retry. The OTP step cannot: the member has answered every
  /// question and passed verification, so the only useful thing left to do is
  /// let them into the app. A profile row already exists by this point —
  /// `syncMatchableFromDraft` writes it on the per-step PATCHes — so what a
  /// failure here costs is the completion flag and percentage, not the
  /// profile, and the next launch's PostAuthDestination check re-runs anyway.
  ///
  /// Returns whether it succeeded, so a caller that does want to react can.
  Future<bool> finalizeOnboardingQuietly() async {
    try {
      await finalizeToBackend();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Flow Mode ───────────────────────────────────────────────────────
  //
  // CREATE and EDIT reuse this exact wizard/review UI — only the mode flag
  // and where the draft data comes from differ.

  /// Switches to CREATE mode with an empty draft — the normal first-time
  /// signup path. Also used to reset state after an EDIT session ends.
  void startCreateMode() {
    enterCreateMode();
    state = const ProfileDraft();
  }

  /// Switches to CREATE mode and keeps whatever the draft already holds.
  ///
  /// For a step that has to guarantee it is not running inside a stale EDIT
  /// session but must not cost the member their answers — Profile For, which
  /// is reachable by Back from the step after it. [startCreateMode] is what
  /// a genuinely new signup calls.
  void enterCreateMode() {
    ref.read(profileFlowModeProvider.notifier).state = ProfileFlowMode.create;
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

  // ─── Step 1: Profile For + Gender ──────────────────────────────────

  /// Step 1 — "Profile For" and "Gender".
  ///
  /// Both land on `BasicDetails`, which is where each of them already lived:
  /// gender did not gain a second home when it moved off the State & City
  /// step, it simply gained an earlier writer. There is exactly one gender
  /// value in the app — `BasicDetails.gender` — and this is one of the two
  /// screens that sets it (the other being the Edit Profile wizard's Basic
  /// Info step).
  ///
  /// Deliberately synchronous and network-free, as this step has always been.
  /// It runs before any credential exists on every signup path, so a PATCH
  /// here would be a guaranteed 401; the values reach the backend through the
  /// same `updateBasicDetails` call they always did — `applyProfileBasics`
  /// mid-flow, and `flushOnboardingToBackend` at the end — both of which send
  /// the whole of `state.basicDetails`, gender included.
  void applyProfileFor(ProfileForForm form) {
    state = state.copyWith(
      basicDetails: state.basicDetails.copyWith(
        profileCreatedFor: form.profileCreatedFor,
        gender: form.gender,
      ),
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
    // A LocalAuthSession counts, because the requests it authorises now
    // genuinely reach the backend (see api_providers' devAuthPhone wiring).
    // Without this the dummy-OTP flow persisted every answer locally and sent
    // none of them, which is why a member could finish onboarding and have no
    // `user_profiles` row at all.
    if (hasLocalAuthSession()) return true;
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
      // Every section but the last is sent with `skipMaterialize: true`.
      // They are all stored either way; what is skipped is the server-side
      // profile write and completion recompute, which only the final call
      // needs to run because only it sees the whole draft. See the comment
      // on that call below.
      await repo.updateBasicDetails(state.basicDetails, skipMaterialize: true);
      await repo.updateReligionDetails(state.religionDetails,
          skipMaterialize: true);
      // `languageDetails` is not optional bookkeeping — `motherTongue` is a
      // NOT NULL column on `user_profiles`, so the profile row cannot be
      // written without it (see isMatchableFromDraft / writeProfileFromDraft).
      //
      // Omitting it here stranded every member who signed up by phone. That
      // path has no session until step 10 mints one, so `_persist` no-ops for
      // all nine earlier steps and this flush is the ONLY thing that ever
      // reaches the backend — the mother tongue collected on the Religion
      // step included. Confirmed against the live API with a fresh account:
      // after the full flush, `draft_data` held basicDetails, religionDetails,
      // locationDetails, physicalDetails, educationDetails and
      // lifestyleDetails but no `languageDetails` at all, materialization was
      // skipped, and `GET /profiles/me` answered 404 — the member landed on
      // Discover with no profile of their own.
      await repo.updateLanguageDetails(state.languageDetails,
          skipMaterialize: true);
      await repo.updateLocationDetails(state.locationDetails,
          skipMaterialize: true);
      await repo.updatePhysicalDetails(state.physicalDetails,
          skipMaterialize: true);
      await repo.updateEducationDetails(state.educationDetails,
          skipMaterialize: true);
      // The LAST call deliberately materializes, and it has to be the last:
      // every section above is already stored by the time it runs, so this
      // one pass sees the complete draft. Letting all seven materialize did
      // the same writeProfileFromDraft + recalculateAndPersistCompletion work
      // seven times over — measured at ~416ms apiece against the Singapore
      // database — to reach a result only the final one could produce.
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

  /// Step 3 — "Your religion". Writes religion + community, the country the
  /// member lives in, and (when ticked) the partner-community preference.
  ///
  /// No longer writes `caste` or `motherTongue`: both moved to the
  /// "Let's build your Profile" step and are written by [applyProfileBasics].
  /// They are still collected, still NOT NULL on `user_profiles`, and still
  /// reach the same two draft sections — only the screen that asks changed.
  /// This method leaves whatever is already stored untouched, so a member
  /// who answered them here before the move keeps their answers.
  Future<void> applyOnboardingReligion(OnboardingReligionForm form) async {
    final previous = state.locationDetails;

    // The country → state → city cascade, applied across a screen boundary.
    //
    // Country is asked here and state/city two steps later, so the usual
    // "changing a parent clears its children" rule cannot live in one
    // widget's setState — a member who backs up, switches India for Canada
    // and goes forward again would otherwise carry Gujarat and Bhavnagar into
    // Canada, which the server rejects outright. Enforcing it here means it
    // holds no matter which route the member took to get back to this step.
    //
    // Compared on the code where there is one, falling back to the label for
    // a draft that predates the master data.
    final countryChanged = form.livingInCode.isNotEmpty
        ? form.livingInCode != previous.countryCode
        : form.livingIn.trim() != previous.country.trim();

    // Religion → Community is the second cascade, and unlike country → state
    // it lives entirely on this screen, so the widget already cleared the
    // community when the religion changed. Both halves are written the same
    // way as the country: the code the server validates, and the label the
    // member reads back on their profile.
    //
    // subCaste is deliberately untouched here. It is asked two steps later as
    // free text, has no master data behind it, and is not a child of
    // community in any dataset this project holds — clearing it on a religion
    // change would discard an answer nothing has invalidated.
    state = state.copyWith(
      religionDetails: state.religionDetails.copyWith(
        religion: form.religion,
        community: form.community,
        religionCode: form.religionCode,
        communityCode: form.communityCode,
      ),
      locationDetails: previous.copyWith(
        country: form.livingIn,
        countryCode: form.livingInCode,
        state: countryChanged ? '' : previous.state,
        stateCode: countryChanged ? '' : previous.stateCode,
        city: countryChanged ? '' : previous.city,
        cityCode: countryChanged ? '' : previous.cityCode,
      ),
    );

    await _persist(() async {
      final repo = ref.read(registrationRepositoryProvider);
      await repo.updateReligionDetails(state.religionDetails,
          skipMaterialize: true);
      await repo.updateLocationDetails(state.locationDetails,
          skipMaterialize: true);
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

  /// Step 2 — "Your name" + "Date of birth". All three land on
  /// `BasicDetails`, so this is one PATCH to the section the wizard's Basic
  /// Info step already owns — no new endpoint, no new draft section.
  ///
  /// `form.dob` is the *parsed* date and is non-null exactly when
  /// [OnboardingNameForm.isComplete] is true, which is what gates the CTA
  /// that calls this. Guarded anyway: writing a null over a stored date
  /// because a caller skipped the gate would silently un-answer the step.
  Future<void> applyOnboardingName(OnboardingNameForm form) async {
    state = state.copyWith(
      basicDetails: state.basicDetails.copyWith(
        firstName: form.firstName.trim(),
        lastName: form.lastName.trim(),
        dob: form.dob ?? state.basicDetails.dob,
      ),
    );
    await _persist(
      () => ref
          .read(registrationRepositoryProvider)
          .updateBasicDetails(state.basicDetails),
    );
  }

  /// Step 5 — "Let's build your Profile": state, city and sub-community.
  ///
  /// Two draft sections, so up to two PATCHes: the backend has no combined
  /// endpoint, and inventing one for onboarding would duplicate what already
  /// works.
  ///
  /// `basicDetails` is PATCHed even though this step collects none of its
  /// fields: it is what carries the gender answered on Profile For and the
  /// name and date of birth answered on Your Name, neither of which sends
  /// anything itself. Dropping it would strand all four.
  Future<void> applyProfileBasics(ProfileBasicsForm form) async {
    // Sub-community is optional, and blanking it is a real answer only when
    // the member had something stored to begin with: an empty box on a step
    // reopened from a draft that never carried the field must not be treated
    // as "clear my sub-caste". Comparing before assigning also keeps the
    // religion PATCH off the wire entirely when nothing about it changed —
    // which matters more now that this step no longer writes `caste`, so a
    // needless PATCH would be sending a section it has nothing to say about.
    final subCommunity = form.subCommunity.trim();
    final subCasteChanged = subCommunity != state.religionDetails.subCaste;

    state = state.copyWith(
      locationDetails: state.locationDetails.copyWith(
        state: form.state,
        city: form.city,
        // The codes travel with the labels — see ProfileBasicsForm. An answer
        // with no code behind it (a draft from before the master data) keeps
        // an empty code rather than a fabricated one.
        stateCode: form.stateCode,
        cityCode: form.cityCode,
      ),
      religionDetails: subCasteChanged
          ? state.religionDetails.copyWith(subCaste: subCommunity)
          : state.religionDetails,
    );
    // Up to three PATCHes: the fields live in two draft sections, plus the
    // religion section on the steps where sub-community actually changed, and
    // the backend has no combined endpoint.
    //
    // All of them skip materialization even though this step supplies several
    // of the columns the profile write needs, because it cannot yet satisfy
    // isMatchableFromDraft: that also requires `maritalStatus`, which the NEXT
    // step collects. A materialize pass here would run the whole
    // write-and-recompute against a draft that must fail the check, and write
    // nothing. See [applyOnboardingMarital], which is the first step that can.
    await _persist(() async {
      final repo = ref.read(registrationRepositoryProvider);
      await repo.updateBasicDetails(state.basicDetails, skipMaterialize: true);
      await repo.updateLocationDetails(state.locationDetails,
          skipMaterialize: true);
      if (subCasteChanged) {
        await repo.updateReligionDetails(state.religionDetails,
            skipMaterialize: true);
      }
    });
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
    // The one step in onboarding that still materializes, and deliberately.
    // `maritalStatus` is the last value isMatchableFromDraft is waiting for,
    // so this is the earliest point a `user_profiles` row can be written at
    // all. Every other step skips the pass and leaves it to the
    // end-of-onboarding flush — but that alone would leave a member who
    // abandons signup partway through with no profile row, where before they
    // had one. One materialize here preserves that, and pays for it once.
    //
    // It runs on the PHYSICAL call, not the basic-details one that carries
    // maritalStatus: the profile write needs every section, so it has to come
    // after the value is stored, and physical-details is the last call that
    // always runs — the lifestyle one below is conditional on diet.
    await _persist(() async {
      final repo = ref.read(registrationRepositoryProvider);
      await repo.updateBasicDetails(state.basicDetails, skipMaterialize: true);
      await repo.updatePhysicalDetails(state.physicalDetails);
      if (form.diet.trim().isNotEmpty) {
        await repo.updateLifestyleDetails(state.lifestyleDetails,
            skipMaterialize: true);
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
          .updateEducationDetails(state.educationDetails,
              skipMaterialize: true),
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
          .updateEducationDetails(state.educationDetails,
              skipMaterialize: true),
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
          .updateLifestyleDetails(state.lifestyleDetails,
              skipMaterialize: true),
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
  // maintaining a synchronized copy. The quiz UI itself never calls this
  // — it displays status by watching myPersonalityResultProvider directly,
  // the same as everywhere else.
  Future<PersonalityResult?> psychologyQuizResult() {
    return ref.read(personalityRepositoryProvider).getMyResult();
  }

  // ─── Step 11: Partner Preference ───────────────────────────────────
  //
  // No wizard-local update-only method — the in-wizard step is now just a
  // CTA card that pushes the standalone Partner Preferences page, which
  // edits and persists in one step via
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
