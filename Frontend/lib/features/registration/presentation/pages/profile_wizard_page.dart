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
import '../widgets/partner_preference_step_card.dart';
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

/// **Edit Profile's section editor.** Opens on one section of an
/// already-finalized profile, saves it, and returns to Discover.
///
/// This screen used to double as a 13-step signup wizard, walked front to
/// back by every new member. That flow is gone: onboarding is now
/// CreateProfileForPage -> ProfileBasicsPage -> Discover, and no sign-up
/// path routes here. What remains is the single-section quick edit that
/// `openEditProfile` and ProfileReviewPage have always pushed — which is
/// why there is no step advancement, no Skip, and no progress chrome here
/// any more. `currentStep` survives as *which section is open*, chosen by
/// the caller through [RegistrationNotifier.goToStep], never walked.
class ProfileWizardPage extends ConsumerStatefulWidget {
  const ProfileWizardPage({super.key});

  @override
  ConsumerState<ProfileWizardPage> createState() => _ProfileWizardPageState();
}

/// Usable body height below which the action bar collapses to a single row
/// — see the comment in [_ProfileWizardPageState.build]. Sits above the
/// tightest viewport that still fits everything and below a landscape phone
/// (~242dp usable) or a portrait one with the keyboard raised (~235dp).
const double _compactChromeThreshold = 420;

class _ProfileWizardPageState extends ConsumerState<ProfileWizardPage> {
  bool _isSaving = false;

  // The draft exactly as it was when this screen was opened (either fresh
  // from startEditMode()'s GET /profiles/draft, or whatever
  // ProfileReviewPage was already holding when the user tapped "Edit" on a
  // section). System/hardware back restores this snapshot instead of
  // leaving whatever the user typed in place, so cancelling an edit never
  // persists — even locally in the shared draft.
  late final ProfileDraft _entryDraft;

  @override
  void initState() {
    super.initState();
    _entryDraft = ref.read(registrationProvider);
  }

  /// Saves the open section, republishes the finalized profile, and returns
  /// to Discover.
  Future<void> _onSave() async {
    StoryPerf.start('Save tapped');
    final notifier = ref.read(registrationProvider.notifier);
    StoryPerf.mark('Local validation complete');

    setState(() => _isSaving = true);
    final ok = await _saveAndFinalizeForEdit(notifier);
    if (!mounted) return;
    setState(() => _isSaving = false);
    StoryPerf.mark('Cubit/state updated (isSaving=false)');
    if (!ok) return;
    _exitEditModeToDiscover(notifier);
  }

  /// Mirrors backend/apps/api/src/modules/profiles/validation/
  /// registration-rules.ts — without this, "Save" would accept a section
  /// with required fields empty, only to have POST /profiles/finalize
  /// reject it with a field name the user has no way to trace back to the
  /// section it came from. Sections 0-3 and 5 are hard-required. Sections
  /// 4, 6 and 8 may be left wholly empty, but once touched every field is
  /// required — see each model's `isValid` getter. Sections 7 (family), 9
  /// (quiz), 10 (partner preference), 11 (photos) and 12 (verification)
  /// have no required fields at all in this release.
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

  /// Single source of truth for cancelling an edit session. Both the
  /// bottom-left Back arrow and system/hardware back (PopScope, below) call
  /// this exact method so their behaviour can never diverge: it leaves Edit
  /// Profile immediately, discarding whatever was typed in this session,
  /// and never calls any save/update/finalize API. Restoring [_entryDraft]
  /// rather than wiping the draft matters when this screen was pushed on
  /// top of ProfileReviewPage (editing a single section): popping must
  /// leave the review screen's other, untouched sections exactly as they
  /// were, not force a full re-fetch.
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

  /// Persists the section currently open and re-finalizes the profile
  /// (idempotent) so Discover/Matches reflect the change. Returns false and
  /// shows an error snackbar on failure.
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
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).registrationSaveChangesErrorDetail(e.message),
          ),
        ),
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).registrationSaveChangesError,
          ),
        ),
      );
      return false;
    }
  }

  /// Resets the flow back to CREATE for hygiene, shows the success
  /// confirmation, and returns to Discover.
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
      SnackBar(
        content: Text(AppLocalizations.of(context).registrationProfileUpdated),
      ),
    );
    StoryPerf.mark('Navigation started (to discover)');
    context.go(RouteNames.discover);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(registrationProvider.notifier);
    // Watches two *derived scalars* rather than the whole ProfileDraft.
    //
    // Every character typed into any field emits a brand-new ProfileDraft,
    // so watching the draft here rebuilt this entire page — PopScope,
    // LayoutBuilder, AnimatedSwitcher and the sticky bottom bar — on every
    // keystroke. Nothing outside the section content depends on the field
    // being typed into: the bar only needs to know whether Save is enabled.
    //
    // `select` compares the *selected value*, not the model, so an int and a
    // bool are enough here — this needs no `operator ==` on ProfileDraft, and
    // adding one would not have helped, since the draft genuinely does change
    // on every keystroke. The full draft is now watched only by the section
    // content itself (see the Consumer below), which is the one part that
    // legitimately depends on it.
    final stepIndex = ref.watch(
      registrationProvider.select((d) => d.currentStep),
    );
    final isStepValid = ref.watch(
      registrationProvider.select(_isCurrentStepValid),
    );

    return PopScope(
      // Edit Profile is a single quick-edit session, not a multi-step form
      // the user is expected to walk backward through — back always exits
      // immediately (see _exitEditProfileWithoutSaving), regardless of
      // which section it was opened on.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitEditProfileWithoutSaving();
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // The action bar occupies unshrinkable height that does not
              // fit a landscape phone (~242dp usable) or a portrait one
              // with the keyboard open (~235dp): Expanded collapsed to zero
              // and the Column still overflowed. Below the threshold the
              // bar collapses to one row so the field being edited and the
              // Save button keep their space.
              final compact = constraints.maxHeight < _compactChromeThreshold;
              return Column(
                children: [
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
                        // The one subtree that genuinely needs the full
                        // draft: each section is seeded from its own slice.
                        // Confining the watch here keeps a keystroke from
                        // rebuilding the bar below it.
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
                    continueLabel: l10n.actionSave,
                    continueIcon: Icons.check_rounded,
                    backLabel: l10n.registrationBack,
                    isLoading: _isSaving,
                    onBack: _isSaving ? null : _exitEditProfileWithoutSaving,
                    // Gate "Save" on the open section's required fields
                    // being present (see [_isCurrentStepValid]) so a user
                    // cannot save empty required fields and hit an
                    // untraceable 400 at finalize.
                    onNext: (_isSaving || !isStepValid) ? null : _onSave,
                    validationHint: (!_isSaving && !isStepValid)
                        ? l10n.registrationRequiredFieldsHint
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
        // part of the draft — StepPhotos manages them directly.
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
