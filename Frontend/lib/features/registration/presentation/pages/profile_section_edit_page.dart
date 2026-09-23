import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/widgets/feedback/error_widget.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../astro/presentation/providers/compatibility_provider.dart';
import '../../../discover/presentation/providers/discover_providers.dart';
import '../../../profile/presentation/providers/profile_dashboard_providers.dart';
import '../../../profile_completion/presentation/providers/profile_completeness_provider.dart';
import '../../data/repositories/registration_repository.dart';
import '../../domain/models/profile_draft.dart';
import '../../domain/models/profile_flow_mode.dart';
import '../providers/registration_provider.dart';
import '../widgets/profile_section_forms.dart';
import '../widgets/registration_sticky_bottom_bar.dart';
import '../widgets/step_family.dart';
import '../widgets/step_horoscope.dart';
import '../widgets/step_photos.dart';

// ─── The section pages ─────────────────────────────────────────────────
//
// One page per profile section, reached from Edit Profile's section list
// (and from the Profile screen for family and horoscope). Each edits and
// saves exactly one draft section through its own `PATCH
// /profiles/draft/<section>` — see RegistrationNotifier's publish* methods.
// There is no page that edits, or saves, more than one section.

/// Basic Information: name, date of birth, profile for, gender, marital
/// status.
class BasicInfoEditPage extends StatelessWidget {
  const BasicInfoEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileSectionEditPage<BasicDetails>(
      title: AppLocalizations.of(context).profileBasicDetailsTitle,
      read: (draft) => draft.basicDetails,
      form: (initial, onChanged) =>
          BasicInfoForm(initial: initial, onChanged: onChanged),
      save: (notifier, value) => notifier.publishBasicDetails(value),
    );
  }
}

/// Religion & Community: religion, community, sub-community.
class ReligionCommunityEditPage extends StatelessWidget {
  const ReligionCommunityEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileSectionEditPage<ReligionDetails>(
      title: AppLocalizations.of(context).registrationReligionTitle,
      read: (draft) => draft.religionDetails,
      form: (initial, onChanged) =>
          ReligionCommunityForm(initial: initial, onChanged: onChanged),
      save: (notifier, value) => notifier.publishReligionDetails(value),
    );
  }
}

/// Location: country, state, city.
class LocationEditPage extends StatelessWidget {
  const LocationEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileSectionEditPage<LocationDetails>(
      title: AppLocalizations.of(context).registrationLocationTitle,
      read: (draft) => draft.locationDetails,
      form: (initial, onChanged) =>
          LocationForm(initial: initial, onChanged: onChanged),
      save: (notifier, value) => notifier.publishLocationDetails(value),
    );
  }
}

/// Education & Work: qualification, college, income, work.
class EducationWorkEditPage extends StatelessWidget {
  const EducationWorkEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileSectionEditPage<EducationDetails>(
      title: AppLocalizations.of(context).registrationEducationTitle,
      read: (draft) => draft.educationDetails,
      form: (initial, onChanged) =>
          EducationWorkForm(initial: initial, onChanged: onChanged),
      save: (notifier, value) => notifier.publishEducationDetails(value),
    );
  }
}

/// Physical Details: height.
class PhysicalDetailsEditPage extends StatelessWidget {
  const PhysicalDetailsEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileSectionEditPage<PhysicalDetails>(
      title: AppLocalizations.of(context).registrationPhysicalTitle,
      read: (draft) => draft.physicalDetails,
      form: (initial, onChanged) =>
          PhysicalDetailsForm(initial: initial, onChanged: onChanged),
      save: (notifier, value) => notifier.publishPhysicalDetails(value),
    );
  }
}

/// Lifestyle & About: diet, about me.
class LifestyleAboutEditPage extends StatelessWidget {
  const LifestyleAboutEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileSectionEditPage<LifestyleDetails>(
      title: AppLocalizations.of(context).registrationLifestyleTitle,
      read: (draft) => draft.lifestyleDetails,
      form: (initial, onChanged) =>
          LifestyleAboutForm(initial: initial, onChanged: onChanged),
      save: (notifier, value) => notifier.publishLifestyleDetails(value),
    );
  }
}

/// Family Details — a separate profile section, not part of Edit Profile's
/// registration list; reached from the Profile screen.
class FamilyDetailsEditPage extends StatelessWidget {
  const FamilyDetailsEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileSectionEditPage<FamilyDetails>(
      title: AppLocalizations.of(context).registrationFamilyTitle,
      read: (draft) => draft.familyDetails,
      form: (initial, onChanged) => StepFamily(
        details: initial,
        onChanged: (value) => onChanged(value, null),
        scrollable: false,
      ),
      // StepBody already pads horizontally.
      bodyPadding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      save: (notifier, value) => notifier.publishFamilyDetails(value),
    );
  }
}

/// Horoscope — a separate profile section. See [FamilyDetailsEditPage].
class HoroscopeDetailsEditPage extends StatelessWidget {
  const HoroscopeDetailsEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ProfileSectionEditPage<HoroscopeDetails>(
      title: AppLocalizations.of(context).registrationHoroscopeTitle,
      read: (draft) => draft.horoscopeDetails,
      form: (initial, onChanged) => StepHoroscope(
        details: initial,
        onChanged: (value) => onChanged(value, null),
        scrollable: false,
      ),
      bodyPadding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      save: (notifier, value) => notifier.publishHoroscopeDetails(value),
    );
  }
}

/// Photos. Not a draft section: photos are their own backend resource
/// (PhotoController), and [StepPhotos] uploads, reorders, deletes and sets
/// the primary photo immediately through it — so this page has no Save, and
/// no draft to load.
class PhotosEditPage extends StatelessWidget {
  const PhotosEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).registrationPhotosTitle),
      ),
      body: const SafeArea(child: StepPhotos()),
    );
  }
}

// ─── Loading the saved profile ─────────────────────────────────────────

/// Whether the shared draft already holds the member's profile: EDIT mode
/// (hydrated by `openEditProfile`), or the end-of-registration review, whose
/// draft is the registration being completed and must not be replaced by a
/// fetch — nor switched into EDIT mode.
bool _draftLoaded(WidgetRef ref) =>
    ref.read(profileFlowModeProvider) == ProfileFlowMode.edit ||
    ref.read(registrationProvider).basicDetails.firstName.isNotEmpty;

/// Shows [builder] once the member's saved profile is in the shared draft.
///
/// Normally it already is, and [builder] runs on the first frame. Opened
/// cold — a deep link, a restored route — it loads the profile with the same
/// `GET /profiles/draft` every Edit Profile entry point uses, behind a
/// spinner, and offers Retry if that fails. Never an empty form: an empty
/// form's Save would write defaults over the member's real answers.
class EditProfileDraftGate extends ConsumerStatefulWidget {
  const EditProfileDraftGate({
    super.key,
    required this.title,
    required this.builder,
  });

  /// The AppBar title shown while loading or after a failed load.
  final String title;
  final WidgetBuilder builder;

  @override
  ConsumerState<EditProfileDraftGate> createState() =>
      _EditProfileDraftGateState();
}

class _EditProfileDraftGateState extends ConsumerState<EditProfileDraftGate> {
  late bool _ready;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _ready = _draftLoaded(ref);
    // After the first frame: startEditMode writes to providers, which
    // Riverpod forbids while this widget tree is still building.
    if (!_ready) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _failed = false);
    try {
      await ref.read(registrationProvider.notifier).startEditMode();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.builder(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: _failed
            ? NmErrorWidget(
                title: AppLocalizations.of(
                  context,
                ).commonProfileLoadConnectionError,
                onRetry: _load,
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

// ─── The page every section editor is built on ─────────────────────────

/// Usable body height below which the action bar collapses to a single row
/// and the AppBar is dropped, so the field being edited and Save keep their
/// room on a landscape phone or behind a raised keyboard.
const double _compactChromeThreshold = 420;

/// Edits one draft section: load, edit, save, discard.
///
/// - Opens on the member's saved values for the section ([read] from the
///   shared draft, loaded by [EditProfileDraftGate] if need be).
/// - The [form] keeps its edits to itself; nothing is written to the draft
///   or the backend until Save.
/// - Save runs [save] once — the section's own PATCH — and ignores further
///   taps while it is in flight. A malformed field (reported by the form)
///   blocks it with a message. A failed save keeps the member here with their
///   edits and the server's message. A successful one refreshes what the
///   Profile screens read and returns to the page this was opened from —
///   Edit Profile's section list, which then shows the new values.
/// - Back (AppBar, bar, system) leaves without saving and calls no API.
class ProfileSectionEditPage<T> extends ConsumerStatefulWidget {
  const ProfileSectionEditPage({
    super.key,
    required this.title,
    required this.read,
    required this.form,
    required this.save,
    this.bodyPadding = const EdgeInsets.all(AppSpacing.lg),
  });

  final String title;

  /// Padding around the form inside the page's scroll view.
  final EdgeInsets bodyPadding;

  /// The section's current value in the shared draft.
  final T Function(ProfileDraft draft) read;

  /// Builds the section's form from its saved value.
  final Widget Function(T initial, SectionFormChanged<T> onChanged) form;

  /// Persists the section. Must throw on failure.
  final Future<void> Function(RegistrationNotifier notifier, T value) save;

  @override
  ConsumerState<ProfileSectionEditPage<T>> createState() =>
      _ProfileSectionEditPageState<T>();
}

class _ProfileSectionEditPageState<T>
    extends ConsumerState<ProfileSectionEditPage<T>> {
  @override
  Widget build(BuildContext context) {
    return EditProfileDraftGate(
      title: widget.title,
      builder: (context) => _SectionEditor<T>(
        title: widget.title,
        initial: widget.read(ref.read(registrationProvider)),
        form: widget.form,
        save: widget.save,
        bodyPadding: widget.bodyPadding,
      ),
    );
  }
}

class _SectionEditor<T> extends ConsumerStatefulWidget {
  const _SectionEditor({
    required this.title,
    required this.initial,
    required this.form,
    required this.save,
    required this.bodyPadding,
  });

  final String title;
  final EdgeInsets bodyPadding;
  final T initial;
  final Widget Function(T initial, SectionFormChanged<T> onChanged) form;
  final Future<void> Function(RegistrationNotifier notifier, T value) save;

  @override
  ConsumerState<_SectionEditor<T>> createState() => _SectionEditorState<T>();
}

class _SectionEditorState<T> extends ConsumerState<_SectionEditor<T>> {
  late T _value = widget.initial;
  String? _error;
  bool _isSaving = false;

  /// Built once: the form owns its fields' state from here on, so it must
  /// not be rebuilt from [widget.initial] as this page rebuilds.
  late final Widget _form = widget.form(widget.initial, (value, error) {
    _value = value;
    _error = error;
  });

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.editProfile);
    }
  }

  void _exitWithoutSaving() {
    if (_isSaving) return;
    _leave();
  }

  Future<void> _onSave() async {
    if (_isSaving) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final error = _error;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.save(ref.read(registrationProvider.notifier), _value);
    } on RegistrationApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.registrationSaveProfileErrorDetail(e.message)),
        ),
      );
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.registrationSaveProfileError)),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isSaving = false);

    // What the Profile screens read, so they show the saved values and the
    // recomputed completion rather than a pre-edit snapshot.
    ref.invalidate(profileDraftResponseProvider);
    ref.invalidate(profileCompletenessSnapshotProvider);
    ref.invalidate(discoverFeedProvider);
    ref.invalidate(myHoroscopeSummaryProvider);

    messenger.showSnackBar(
      SnackBar(content: Text(l10n.registrationProfileUpdated)),
    );
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Measured without viewInsets, so the AppBar does not come and go with
    // the keyboard.
    final orientationHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.paddingOf(context).vertical;
    final showAppBar = orientationHeight >= _compactChromeThreshold;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitWithoutSaving();
      },
      child: Scaffold(
        appBar: showAppBar
            ? AppBar(
                title: Text(widget.title),
                leading: BackButton(
                  onPressed: _isSaving ? null : _exitWithoutSaving,
                ),
              )
            : null,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < _compactChromeThreshold;
              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: widget.bodyPadding,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: _form,
                    ),
                  ),
                  RegistrationStickyBottomBar(
                    compact: compact,
                    continueLabel: l10n.actionSave,
                    continueIcon: Icons.check_rounded,
                    backLabel: l10n.registrationBack,
                    isLoading: _isSaving,
                    onBack: _isSaving ? null : _exitWithoutSaving,
                    onNext: _isSaving ? null : _onSave,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
