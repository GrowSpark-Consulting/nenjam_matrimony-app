import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/utils/story_perf.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../discover/presentation/providers/discover_providers.dart';
import '../../../profile/presentation/providers/profile_dashboard_providers.dart';
import '../../../profile_completion/presentation/providers/profile_completeness_provider.dart';
import '../../data/repositories/registration_repository.dart';
import '../../domain/models/profile_draft.dart';
import '../../domain/models/profile_flow_mode.dart';
import '../providers/registration_provider.dart';
import '../utils/registration_milestones.dart';
import '../utils/registration_motivation.dart';
import '../utils/registration_time_estimate.dart';
import '../widgets/partner_preference_step_card.dart';
import '../widgets/registration_journey_header.dart';
import '../widgets/registration_motivation_caption.dart';
import '../widgets/registration_sticky_bottom_bar.dart';
import '../widgets/step_basic_info.dart';
import '../widgets/step_education.dart';
import '../widgets/step_family.dart';
import '../widgets/step_horoscope.dart';
import '../widgets/step_language.dart';
import '../widgets/step_lifestyle.dart';
import '../widgets/step_location.dart';
import '../widgets/step_photos.dart';
import '../widgets/step_physical.dart';
import '../widgets/step_psychological_quiz.dart';
import '../widgets/step_religion.dart';
import '../widgets/step_verification.dart';

/// Container wizard screen hosting all 13 registration steps.
class ProfileWizardPage extends ConsumerStatefulWidget {
  const ProfileWizardPage({super.key});

  @override
  ConsumerState<ProfileWizardPage> createState() => _ProfileWizardPageState();
}

/// Usable body height below which the wizard drops its progress chrome —
/// see the comment in [_ProfileWizardPageState.build]. Sits above the
/// tightest viewport that still fits everything (a 320x568 phone leaves
/// 490dp) and below a landscape phone (~242dp) or a portrait one with the
/// keyboard raised (~235dp).
const double _compactChromeThreshold = 420;

class _ProfileWizardPageState extends ConsumerState<ProfileWizardPage> {
  bool _isSaving = false;

  // EDIT MODE only — the draft exactly as it was when this wizard screen
  // was opened (either fresh from startEditMode()'s GET /profiles/draft, or
  // whatever ProfileReviewPage was already holding when the user tapped
  // "Edit" on a section). System/hardware back restores this snapshot
  // instead of leaving whatever the user typed in place, so cancelling an
  // edit never persists — even locally in the shared draft — and never
  // steps backward through the wizard the way CREATE mode's Back does.
  late final ProfileDraft _entryDraft;

  @override
  void initState() {
    super.initState();
    _entryDraft = ref.read(registrationProvider);
  }

  Future<void> _onNext() async {
    StoryPerf.start('Continue tapped');
    final draft = ref.read(registrationProvider);
    final notifier = ref.read(registrationProvider.notifier);
    StoryPerf.mark('Local validation complete');

    // EDIT MODE: this is a single-section quick edit (opened from the
    // drawer via Edit Profile / Verification Center) — save just this
    // section, republish the finalized profile, and go straight back to
    // Discover. Never advance through the remaining wizard steps or
    // restart registration/onboarding.
    if (ref.read(profileFlowModeProvider) == ProfileFlowMode.edit) {
      StoryPerf.mark('Mode: EDIT');
      setState(() => _isSaving = true);
      final ok = await _saveAndFinalizeForEdit(notifier);
      if (!mounted) return;
      setState(() => _isSaving = false);
      StoryPerf.mark('Cubit/state updated (isSaving=false)');
      if (!ok) return;
      _exitEditModeToDiscover(notifier);
      return;
    }

    StoryPerf.mark('Mode: CREATE');
    setState(() => _isSaving = true);
    final ok = await _syncCurrentStep(notifier);
    StoryPerf.mark('Flutter response received');
    if (!mounted) return;
    setState(() => _isSaving = false);
    StoryPerf.mark('Cubit/state updated (isSaving=false)');
    if (!ok) return;

    if (draft.currentStep < ProfileDraft.totalSteps - 1) {
      StoryPerf.mark('Navigation started (step index change)');
      notifier.nextStep();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        StoryPerf.mark('Next registration page rendered');
      });
    } else {
      StoryPerf.mark('Navigation started (to profileReview)');
      context.go(RouteNames.profileReview);
    }
  }

  /// Persists the current step's data to the backend. Shared by the
  /// "Continue" and "Save & Exit" CREATE-mode actions so the save/error
  /// handling only lives in one place. Shows an error snackbar and returns
  /// false on failure.
  Future<bool> _syncCurrentStep(RegistrationNotifier notifier) async {
    try {
      await notifier.syncCurrentStepToBackend();
      return true;
    } on RegistrationApiException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).registrationSaveStepErrorDetail(e.message))),
      );
      return false;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[RegistrationSave] DioException: ${e.type}, status ${e.response?.statusCode}',
        );
      }
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).registrationSaveStepError),
        ),
      );
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RegistrationSave] Unexpected error: ${e.runtimeType}');
      }
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).registrationSaveStepError),
        ),
      );
      return false;
    }
  }

  /// Mirrors backend/apps/api/src/modules/profiles/validation/
  /// registration-rules.ts — without this, "Continue" would let a user
  /// click through the whole wizard with required fields empty, only to
  /// have POST /profiles/finalize reject it at the very last step with a
  /// field name they'd have no way to trace back to which step it came
  /// from. Steps 0-3 and 5 are hard-required (no skip). Steps 4, 6, and 8
  /// are skippable, but once touched every field is required — see each
  /// model's `isValid` getter. Steps 7 (family), 9 (quiz), 10 (partner
  /// preference), 11 (photos), and 12 (verification) have no required
  /// fields at all in this release — only Steps 0-3 are mandatory for
  /// registration/Discover access, so Continue must never block on a photo
  /// or on mobile verification (see ProfileService.finalize on the
  /// backend, which no longer gates on either).
  bool _isCurrentStepValid(ProfileDraft draft) {
    switch (draft.currentStep) {
      case 0:
        return draft.basicDetails.isComplete;
      case 1:
        return draft.religionDetails.isComplete;
      case 2:
        return draft.languageDetails.isComplete;
      case 3:
        return draft.locationDetails.isComplete;
      case 4:
        return draft.educationDetails.isValid;
      case 5:
        return draft.physicalDetails.isValid;
      case 6:
        return draft.lifestyleDetails.isValid;
      case 8:
        return draft.horoscopeDetails.isValid;
      default:
        return true;
    }
  }

  /// Steps that show a "Skip" action alongside Continue. Every step here
  /// already lets Continue through when left untouched (see
  /// [_isCurrentStepValid]) — Skip exists as an explicit, discoverable
  /// affordance rather than a functional requirement, and clears any
  /// partial input for that section so a half-filled step can't get stuck
  /// (see [_onSkip]). Steps 0-3 (Basic/Religion/Language/Location) are
  /// deliberately NOT here — those four stay hard-required, no Skip. Step 9
  /// (Discover Personality) also has no entry — it already lets Continue
  /// through unconditionally and its own quiz UI is unchanged.
  bool _isStepSkippable(int step) => const {4, 5, 6, 7, 8, 10}.contains(step);

  /// Clears the current (skippable) step's section back to its empty
  /// default — both locally and, via [_onNext]'s sync, on the backend —
  /// then advances. Clearing on the backend matters: finalize() validates
  /// against RegistrationStep.draftData as persisted server-side, not
  /// against in-memory Flutter state, so a partial fill that's merely
  /// hidden locally would still fail finalize() later.
  Future<void> _onSkip() async {
    final notifier = ref.read(registrationProvider.notifier);
    switch (ref.read(registrationProvider).currentStep) {
      case 4:
        notifier.updateEducationDetails(const EducationDetails());
      case 5:
        notifier.updatePhysicalDetails(const PhysicalDetails());
      case 6:
        notifier.updateLifestyleDetails(const LifestyleDetails());
      case 7:
        notifier.updateFamilyDetails(const FamilyDetails());
      case 8:
        notifier.updateHoroscopeDetails(const HoroscopeDetails());
    }
    await _onNext();
  }

  void _onBack() {
    final draft = ref.read(registrationProvider);
    if (draft.currentStep > 0) {
      ref.read(registrationProvider.notifier).previousStep();
    } else {
      context.pop();
    }
  }

  /// EDIT MODE only — single source of truth for cancelling an edit
  /// session. Both the bottom-left Back arrow and system/hardware back
  /// (PopScope, below) call this exact method so their behaviour can never
  /// diverge: it must leave Edit Profile immediately, discarding whatever
  /// was typed in this session, rather than stepping backward through
  /// wizard steps the way CREATE mode's [_onBack] does — and it must never
  /// call any save/update/finalize API. Restoring [_entryDraft] rather than
  /// wiping the draft matters when this wizard was pushed on top of
  /// ProfileReviewPage (editing a single section): popping must leave the
  /// review screen's other, untouched sections exactly as they were, not
  /// force a full re-fetch.
  void _exitEditProfileWithoutSaving() {
    if (_isSaving) return; // guard against duplicate execution mid-save
    ref
        .read(registrationProvider.notifier)
        .restore(_entryDraft, ProfileFlowMode.edit);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.discover);
    }
  }

  /// EDIT MODE only — persists the section currently open and re-finalizes
  /// the profile (idempotent) so Discover/Matches reflect the change.
  /// Returns false and shows an error snackbar on failure.
  Future<bool> _saveAndFinalizeForEdit(RegistrationNotifier notifier) async {
    try {
      // skipMaterialize: true — finalizeToBackend() runs unconditionally
      // right below and redoes the same materialize+recompute work this
      // step-save would otherwise trigger server-side, so doing it here too
      // would just be duplicate work discarded a moment later.
      await notifier.syncCurrentStepToBackend(skipMaterialize: true);
      StoryPerf.mark('PATCH response received');
      StoryPerf.mark('finalize started');
      await notifier.finalizeToBackend();
      StoryPerf.mark('finalize response received');
      return true;
    } on RegistrationApiException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).registrationSaveChangesErrorDetail(e.message))),
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).registrationSaveChangesError),
        ),
      );
      return false;
    }
  }

  /// EDIT MODE only — resets the flow back to CREATE for hygiene, shows
  /// the success confirmation, and returns to Discover (never onboarding).
  void _exitEditModeToDiscover(RegistrationNotifier notifier) {
    notifier.startCreateMode();
    // Mirrors ProfileReviewPage._onEnterApp()'s edit-mode success handling —
    // the backend has already recomputed completion inside finalizeToBackend()
    // (awaited by the caller before this runs), so refetching these here is
    // what makes the drawer/Profile dashboard show the new percentage/fields
    // immediately, without requiring a separate trip through
    // Edit Profile -> Save Changes to pick up the same data.
    ref.invalidate(profileDraftResponseProvider);
    ref.invalidate(profileCompletenessSnapshotProvider);
    // discoverFeedProvider is a plain (non-autoDispose) FutureProvider kept
    // alive by the always-mounted Discover screen — invalidate it so a user
    // who just created their first user_profiles row (e.g. after the
    // height_cm P2011 regression) sees the real feed instead of a cached
    // "INCOMPLETE_SELF_PROFILE" empty state from before this save.
    ref.invalidate(discoverFeedProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).registrationProfileUpdated)),
    );
    StoryPerf.mark('Navigation started (to discover)');
    context.go(RouteNames.discover);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StoryPerf.mark('Next registration page rendered');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(registrationProvider.notifier);
    // Watches two *derived scalars* rather than the whole ProfileDraft.
    //
    // Every character typed into any wizard field emits a brand-new
    // ProfileDraft, so watching the draft here rebuilt this entire page —
    // PopScope, LayoutBuilder, journey header, motivation caption,
    // AnimatedSwitcher and the sticky bottom bar — on every keystroke.
    // Nothing above the step content actually depends on the field being
    // typed into: the header and bar need the step number, and the bar needs
    // to know whether Continue is enabled.
    //
    // `select` compares the *selected value*, not the model, so an int and a
    // bool are enough here — this needs no `operator ==` on ProfileDraft, and
    // adding one would not have helped, since the draft genuinely does change
    // on every keystroke. The full draft is now watched only by the step
    // content itself (see the Consumer below), which is the one part that
    // legitimately depends on it.
    final stepIndex = ref.watch(
      registrationProvider.select((d) => d.currentStep),
    );
    final isStepValid = ref.watch(
      registrationProvider.select(_isCurrentStepValid),
    );
    final mode = ref.watch(profileFlowModeProvider);
    final isEditMode = mode == ProfileFlowMode.edit;
    final isLastStep = stepIndex == ProfileDraft.totalSteps - 1;
    final (_, milestoneLabel) = milestoneEmojiAndLabel(
      l10n,
      milestoneForStep(stepIndex),
    );

    return PopScope(
      // CREATE mode: system back (Android hardware back / iOS swipe) must
      // behave exactly like the on-screen back button — step backward
      // through the wizard one step at a time, not jump straight out of the
      // whole 13-step flow. Only the real route pop is allowed once already
      // on step 0, mirroring _onBack()'s own logic.
      //
      // EDIT mode: Edit Profile is a single quick-edit session, not a
      // multi-step wizard the user is expected to walk backward through —
      // back must always exit immediately (see _exitEditProfileWithoutSaving),
      // regardless of which step it was opened on.
      canPop: !isEditMode && stepIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isEditMode) {
          _exitEditProfileWithoutSaving();
        } else {
          _onBack();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The journey header and motivation caption are progress
              // chrome, not input. Together with the sticky action bar they
              // occupy ~270dp of unshrinkable height, which does not fit a
              // landscape phone (~242dp usable) or a portrait one with the
              // keyboard open (~235dp): Expanded collapsed to zero and the
              // Column still overflowed, by up to 168dp. Below the
              // threshold they step aside so the field being edited and the
              // Continue button keep their space.
              final compact =
                  constraints.maxHeight < _compactChromeThreshold;
              return Column(
                children: [
                  if (!compact) ...[
                    RegistrationJourneyHeader(
                      stepIndex: stepIndex,
                      totalSteps: ProfileDraft.totalSteps,
                    ),
                    RegistrationMotivationCaption(
                      stepIndex: stepIndex,
                      caption: motivationCaption(l10n, stepIndex),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey<int>(stepIndex),
                    // The one subtree that genuinely needs the full draft:
                    // each step is seeded from its own section. Confining the
                    // watch here keeps a keystroke from rebuilding the
                    // chrome above and below it.
                    child: Consumer(
                      builder: (context, ref, _) => _buildStepContent(
                        stepIndex,
                        ref.watch(registrationProvider),
                        notifier,
                      ),
                    ),
                  ),
                ),
              ),
              RegistrationStickyBottomBar(
                compact: compact,
                milestoneLabel: milestoneLabel,
                estimatedTimeLabel: estimatedTimeRemainingLabel(
                  l10n,
                  stepIndex,
                ),
                continueLabel: isLastStep
                    ? l10n.registrationFinishLogin
                    : l10n.registrationContinueYourStory,
                continueIcon: isLastStep
                    ? Icons.check_rounded
                    : Icons.arrow_forward_rounded,
                backLabel: l10n.registrationBack,
                // Edit Profile keeps the same Back arrow as registration —
                // only its behaviour differs (see
                // _exitEditProfileWithoutSaving): it discards this
                // session's draft and exits straight to Profile Drawer
                // instead of stepping backward. Same method the PopScope
                // above calls for system/gesture back, so the two paths
                // can never diverge.
                showBack: isEditMode || stepIndex > 0,
                isLoading: _isSaving,
                onBack: _isSaving
                    ? null
                    : (isEditMode ? _exitEditProfileWithoutSaving : _onBack),
                // Gate "Continue" on the current step's required fields being
                // present (see [_isCurrentStepValid]) so a user can't click
                // through with empty required fields and hit an untraceable
                // 400 at finalize.
                onNext: (_isSaving || !isStepValid) ? null : _onNext,
                skipLabel: _isStepSkippable(stepIndex)
                    ? l10n.registrationSkipStep
                    : null,
                onSkip: (_isSaving || !_isStepSkippable(stepIndex))
                    ? null
                    : _onSkip,
                validationHint: (!_isSaving && !isStepValid)
                    ? (stepIndex == 12
                        ? l10n.registrationVerifyMobileRequiredHint
                        : l10n.registrationRequiredFieldsHint)
                    : null,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(
    int step,
    ProfileDraft draft,
    RegistrationNotifier notifier,
  ) {
    switch (step) {
      case 0:
        return StepBasicInfo(
          details: draft.basicDetails,
          onChanged: notifier.updateBasicDetails,
        );
      case 1:
        return StepReligion(
          details: draft.religionDetails,
          onChanged: notifier.updateReligionDetails,
        );
      case 2:
        return StepLanguage(
          details: draft.languageDetails,
          onChanged: notifier.updateLanguageDetails,
        );
      case 3:
        return StepLocation(
          details: draft.locationDetails,
          onChanged: notifier.updateLocationDetails,
        );
      case 4:
        return StepEducation(
          details: draft.educationDetails,
          onChanged: notifier.updateEducationDetails,
        );
      case 5:
        return StepPhysical(
          details: draft.physicalDetails,
          onChanged: notifier.updatePhysicalDetails,
        );
      case 6:
        return StepLifestyle(
          details: draft.lifestyleDetails,
          onChanged: notifier.updateLifestyleDetails,
        );
      case 7:
        return StepFamily(
          details: draft.familyDetails,
          onChanged: notifier.updateFamilyDetails,
        );
      case 8:
        return StepHoroscope(
          details: draft.horoscopeDetails,
          onChanged: notifier.updateHoroscopeDetails,
        );
      case 9:
        return const StepPsychologicalQuiz();
      case 10:
        return PartnerPreferenceStepCard(details: draft.partnerPreference);
      case 11:
        // Photos are an independent backend resource (PhotoController), not
        // part of the wizard draft — StepPhotos manages them directly.
        return const StepPhotos();
      case 12:
        return StepVerification(
          status: draft.verificationStatus,
          onChanged: notifier.updateVerificationStatus,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
