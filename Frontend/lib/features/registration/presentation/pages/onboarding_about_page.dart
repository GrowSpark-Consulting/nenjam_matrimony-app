import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/inputs/bio_textarea.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/models/profile_draft.dart';
import '../providers/registration_provider.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 9 — "About yourself".
///
/// Opens on a draft description assembled from what the member has already
/// told us, so the field is never a blank page. It is only a starting point:
/// the text is fully editable, and whatever the member leaves in the box is
/// what gets saved. A description they have already written is never
/// overwritten by the generated one.
class OnboardingAboutPage extends ConsumerStatefulWidget {
  const OnboardingAboutPage({super.key});

  @override
  ConsumerState<OnboardingAboutPage> createState() =>
      _OnboardingAboutPageState();
}

class _OnboardingAboutPageState extends ConsumerState<OnboardingAboutPage> {
  late final TextEditingController _controller;
  String _text = '';

  @override
  void initState() {
    super.initState();
    final draft = ref.read(registrationProvider);
    final existing = draft.lifestyleDetails.aboutMe.trim();
    _text = existing.isNotEmpty ? existing : _suggestion(draft);
    _controller = TextEditingController(text: _text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A first draft in the member's voice, built only from answers they have
  /// already given. Deliberately plain: it is meant to be edited, and an
  /// over-written paragraph is harder to make your own than a short one.
  static String _suggestion(ProfileDraft draft) {
    final sentences = <String>[];

    final work = draft.educationDetails.occupation.trim();
    final qualification = draft.educationDetails.qualification.trim();
    if (work.isNotEmpty && qualification.isNotEmpty) {
      sentences.add('I studied $qualification and work as a $work.');
    } else if (work.isNotEmpty) {
      sentences.add('I work as a $work.');
    } else if (qualification.isNotEmpty) {
      sentences.add('I studied $qualification.');
    }

    final city = draft.locationDetails.city.trim();
    if (city.isNotEmpty) sentences.add('I live in $city.');

    sentences.add(
      'I value honesty and family, and I am looking for someone I can '
      'build a calm, supportive life with.',
    );
    return sentences.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final isComplete = _text.trim().isNotEmpty;

    return OnboardingStepScaffold(
      eyebrow: l10n.onboardingAboutEyebrow,
      headline: l10n.onboardingAboutHeadline,
      crestIcon: Icons.edit_note_rounded,
      backRoute: RouteNames.onboardingPhotos,
      nextRoute: RouteNames.onboardingVerifyMobile,
      isComplete: isComplete,
      validationNames: [if (!isComplete) l10n.onboardingAboutHeadline],
      onSave: () => ref
          .read(registrationProvider.notifier)
          .applyOnboardingAbout(_text.trim()),
      fields: [
        // Reuses the design system's bio field, which already owns the
        // character counter and the app's maximum length.
        NmBioTextArea(
          controller: _controller,
          onChanged: (v) => setState(() => _text = v),
        ),
      ],
      trailing: Text(
        l10n.onboardingAboutHelper,
        style: AppTypography.labelSmall.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
