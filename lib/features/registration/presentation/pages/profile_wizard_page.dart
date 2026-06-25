import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/gradient_button.dart';
import '../../../../core/widgets/buttons/outlined_button.dart';
import '../../domain/models/profile_draft.dart';
import '../providers/registration_provider.dart';
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
import '../widgets/step_religion.dart';
import '../widgets/step_verification.dart';

/// Container wizard screen hosting all 12 registration steps.
class ProfileWizardPage extends ConsumerStatefulWidget {
  const ProfileWizardPage({super.key});

  @override
  ConsumerState<ProfileWizardPage> createState() => _ProfileWizardPageState();
}

class _ProfileWizardPageState extends ConsumerState<ProfileWizardPage> {
  static const _stepTitles = [
    'Basic Info',
    'Religion',
    'Language',
    'Location',
    'Education',
    'Physical',
    'Lifestyle',
    'Family',
    'Horoscope',
    'Preferences',
    'Photos',
    'Verification',
  ];

  void _onNext() {
    final draft = ref.read(registrationProvider);
    if (draft.currentStep < ProfileDraft.totalSteps - 1) {
      ref.read(registrationProvider.notifier).nextStep();
    } else {
      context.push(RouteNames.login);
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

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(registrationProvider);
    final notifier = ref.read(registrationProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stepIndex = draft.currentStep;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _onBack),
        title: Text(
          'Step ${stepIndex + 1} of ${ProfileDraft.totalSteps}',
          style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: () => context.push(RouteNames.login),
            child: Text(
              'Save & Exit',
              style: AppTypography.labelLarge.copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(
            value: (stepIndex + 1) / ProfileDraft.totalSteps,
            backgroundColor: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 6,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              color: isDark ? AppColors.surfaceVariantDark.withValues(alpha: 0.3) : AppColors.surfaceVariantLight.withValues(alpha: 0.5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _stepTitles[stepIndex],
                    style: AppTypography.titleSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${draft.completionPercentage.toInt()}% Completed',
                    style: AppTypography.labelSmall.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey<int>(stepIndex),
                  child: _buildStepContent(stepIndex, draft, notifier),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (stepIndex > 0) ...[
                    Expanded(
                      flex: 1,
                      child: NmOutlinedButton(
                        label: 'Back',
                        onPressed: _onBack,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    flex: 2,
                    child: NmGradientButton(
                      label: stepIndex == ProfileDraft.totalSteps - 1 ? 'Finish & Login' : 'Continue',
                      icon: stepIndex == ProfileDraft.totalSteps - 1 ? Icons.check_rounded : Icons.arrow_forward_rounded,
                      onPressed: _onNext,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(int step, ProfileDraft draft, RegistrationNotifier notifier) {
    switch (step) {
      case 0:
        return StepBasicInfo(details: draft.basicDetails, onChanged: notifier.updateBasicDetails);
      case 1:
        return StepReligion(details: draft.religionDetails, onChanged: notifier.updateReligionDetails);
      case 2:
        return StepLanguage(details: draft.languageDetails, onChanged: notifier.updateLanguageDetails);
      case 3:
        return StepLocation(details: draft.locationDetails, onChanged: notifier.updateLocationDetails);
      case 4:
        return StepEducation(details: draft.educationDetails, onChanged: notifier.updateEducationDetails);
      case 5:
        return StepPhysical(details: draft.physicalDetails, onChanged: notifier.updatePhysicalDetails);
      case 6:
        return StepLifestyle(details: draft.lifestyleDetails, onChanged: notifier.updateLifestyleDetails);
      case 7:
        return StepFamily(details: draft.familyDetails, onChanged: notifier.updateFamilyDetails);
      case 8:
        return StepHoroscope(details: draft.horoscopeDetails, onChanged: notifier.updateHoroscopeDetails);
      case 9:
        return StepPartnerPref(details: draft.partnerPreference, onChanged: notifier.updatePartnerPreference);
      case 10:
        return StepPhotos(gallery: draft.photoGallery, onChanged: notifier.updatePhotoGallery);
      case 11:
        return StepVerification(status: draft.verificationStatus, onChanged: notifier.updateVerificationStatus);
      default:
        return const SizedBox.shrink();
    }
  }
}
