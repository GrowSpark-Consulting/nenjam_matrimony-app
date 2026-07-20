import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/repositories/registration_repository.dart';
import '../../domain/models/profile_draft.dart';
import '../../domain/models/profile_flow_mode.dart';
import '../providers/registration_provider.dart';
import '../utils/registration_milestones.dart';
import '../utils/registration_motivation.dart';
import '../utils/registration_time_estimate.dart';
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
import '../widgets/step_partner_pref.dart';
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

class _ProfileWizardPageState extends ConsumerState<ProfileWizardPage> {
  bool _isSaving = false;

  Future<void> _onNext() async {
    final draft = ref.read(registrationProvider);
    final notifier = ref.read(registrationProvider.notifier);

    // EDIT MODE: this is a single-section quick edit (opened from the
    // drawer via Edit Profile / Verification Center) — save just this
    // section, republish the finalized profile, and go straight back to
    // Discover. Never advance through the remaining wizard steps or
    // restart registration/onboarding.
    if (ref.read(profileFlowModeProvider) == ProfileFlowMode.edit) {
      setState(() => _isSaving = true);
      final ok = await _saveAndFinalizeForEdit(notifier);
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (!ok) return;
      _exitEditModeToDiscover(notifier);
      return;
    }

    setState(() => _isSaving = true);
    final ok = await _syncCurrentStep(notifier);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!ok) return;

    if (draft.currentStep < ProfileDraft.totalSteps - 1) {
      notifier.nextStep();
    } else {
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
        SnackBar(content: Text('Could not save this step: ${e.message}')),
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
        const SnackBar(
          content: Text('Could not save this step. Check your connection.'),
        ),
      );
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RegistrationSave] Unexpected error: ${e.runtimeType}');
      }
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save this step. Check your connection.'),
        ),
      );
      return false;
    }
  }

  /// Mirrors ProfileService.assertRequiredFieldsPresent on the backend —
  /// without this, "Continue" let a user click through the whole wizard
  /// with required fields empty, only to have POST /profiles/finalize
  /// reject it at the very last step with a field name they'd have no way
  /// to trace back to which step it came from. Steps without a case here
  /// (lifestyle, family, horoscope, partner preference, photos,
  /// verification) have no required backend fields.
  bool _isCurrentStepValid(ProfileDraft draft) {
    switch (draft.currentStep) {
      case 0:
        return draft.basicDetails.firstName.isNotEmpty &&
            draft.basicDetails.lastName.isNotEmpty &&
            draft.basicDetails.gender.isNotEmpty &&
            draft.basicDetails.dob != null;
      case 1:
        return draft.religionDetails.religion.isNotEmpty &&
            draft.religionDetails.caste.isNotEmpty;
      case 2:
        return draft.languageDetails.motherTongue.isNotEmpty;
      case 3:
        return draft.locationDetails.city.isNotEmpty &&
            draft.locationDetails.state.isNotEmpty;
      case 4:
        return draft.educationDetails.qualification.isNotEmpty &&
            draft.educationDetails.occupation.isNotEmpty;
      case 5:
        return draft.physicalDetails.height.isNotEmpty;
      default:
        return true;
    }
  }

  void _onBack() {
    final draft = ref.read(registrationProvider);
    if (draft.currentStep > 0) {
      ref.read(registrationProvider.notifier).previousStep();
    } else {
      context.pop();
    }
  }

  /// CREATE MODE: persists progress on the current step and returns to
  /// Profile Review, so the user can resume editing any section later
  /// instead of losing what they've entered so far.
  /// EDIT MODE: saves the section being edited and returns to Discover.
  Future<void> _onSaveExit() async {
    final notifier = ref.read(registrationProvider.notifier);

    if (ref.read(profileFlowModeProvider) == ProfileFlowMode.edit) {
      setState(() => _isSaving = true);
      final ok = await _saveAndFinalizeForEdit(notifier);
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (!ok) return;
      _exitEditModeToDiscover(notifier);
      return;
    }

    setState(() => _isSaving = true);
    final ok = await _syncCurrentStep(notifier);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!ok) return;
    context.go(RouteNames.profileReview);
  }

  /// EDIT MODE only — persists the section currently open and re-finalizes
  /// the profile (idempotent) so Discover/Matches reflect the change.
  /// Returns false and shows an error snackbar on failure.
  Future<bool> _saveAndFinalizeForEdit(RegistrationNotifier notifier) async {
    try {
      await notifier.syncCurrentStepToBackend();
      await notifier.finalizeToBackend();
      return true;
    } on RegistrationApiException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save your changes: ${e.message}')),
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your changes. Check your connection.'),
        ),
      );
      return false;
    }
  }

  /// EDIT MODE only — resets the flow back to CREATE for hygiene, shows
  /// the success confirmation, and returns to Discover (never onboarding).
  void _exitEditModeToDiscover(RegistrationNotifier notifier) {
    notifier.startCreateMode();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated successfully')),
    );
    context.go(RouteNames.discover);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = ref.watch(registrationProvider);
    final notifier = ref.read(registrationProvider.notifier);
    final stepIndex = draft.currentStep;
    final isLastStep = stepIndex == ProfileDraft.totalSteps - 1;
    final (_, milestoneLabel) = milestoneEmojiAndLabel(
      l10n,
      milestoneForStep(stepIndex),
    );

    return PopScope(
      // System back (Android hardware back / iOS swipe) must behave
      // exactly like the on-screen back button — step backward through the
      // wizard one step at a time, not jump straight out of the whole
      // 13-step flow. Only the real route pop is allowed once already on
      // step 0, mirroring _onBack()'s own logic.
      canPop: stepIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              RegistrationJourneyHeader(
                stepIndex: stepIndex,
                totalSteps: ProfileDraft.totalSteps,
                onBack: _onBack,
                onSaveExit: _isSaving ? null : _onSaveExit,
              ),
              RegistrationMotivationCaption(
                stepIndex: stepIndex,
                caption: motivationCaption(l10n, stepIndex),
              ),
              const SizedBox(height: 12),
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
                    child: _buildStepContent(stepIndex, draft, notifier),
                  ),
                ),
              ),
              RegistrationStickyBottomBar(
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
                showBack: stepIndex > 0,
                isLoading: _isSaving,
                onBack: _isSaving ? null : _onBack,
                // Gate "Continue" on the current step's required fields being
                // present (see [_isCurrentStepValid]) so a user can't click
                // through with empty required fields and hit an untraceable
                // 400 at finalize.
                onNext:
                    (_isSaving || !_isCurrentStepValid(draft)) ? null : _onNext,
              ),
            ],
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
        return StepPartnerPref(
          details: draft.partnerPreference,
          onChanged: notifier.updatePartnerPreference,
        );
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
