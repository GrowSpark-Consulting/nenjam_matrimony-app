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
import '../widgets/registration_sticky_bottom_bar.dart';
import '../widgets/step_basic_info.dart';
import '../widgets/step_body.dart';
import '../widgets/step_education.dart';
import '../widgets/step_family.dart';
import '../widgets/step_horoscope.dart';
import '../widgets/step_language.dart';
import '../widgets/step_lifestyle.dart';
import '../widgets/step_location.dart';
import '../widgets/step_photos.dart';
import '../widgets/step_physical.dart';
import '../widgets/step_religion.dart';

/// **Edit Profile's editor: one scrollable page holding every editable
/// section.**
///
/// Replaces the per-section flow that used to live in ProfileWizardPage,
/// where tapping "Edit" on the summary opened that one section on a page of
/// its own and saving it returned the member to Discover — so editing two
/// sections meant walking that round trip twice. The sections themselves are
/// unchanged: the same widgets, controllers, validation and draft slices,
/// now built with `scrollable: false` (see [StepBody]) and stacked inside
/// the single viewport this page owns.
///
/// Not every summary row lands here. The psychological quiz, partner
/// preferences and verification are not field groups; they are separate
/// features with pages of their own, and the summary links straight to those.
///
/// [initialSection] scrolls to one section on open, so the deep entry points
/// that used to name a wizard step (`openEditProfile(wizardStep: n)`, from
/// the Profile dashboard and the completion checklist) still land where they
/// always did.
class ProfileEditPage extends ConsumerStatefulWidget {
  /// Draft step index of the section to scroll to on open, or null to open at
  /// the top. These are [ProfileDraft]'s indices, so callers keep passing the
  /// values they always have.
  final int? initialSection;

  const ProfileEditPage({super.key, this.initialSection});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

/// Usable body height below which the action bar collapses to a single row.
/// Carried over from ProfileWizardPage unchanged: it sits above the tightest
/// viewport that still fits everything and below a landscape phone (~242dp
/// usable) or a portrait one with the keyboard raised (~235dp).
const double _compactChromeThreshold = 420;

/// The editable sections, in the order the summary lists them. The indices
/// are [ProfileDraft] step indices — deliberately not contiguous, because
/// they are also the values [ProfileEditPage.initialSection] is given by the
/// callers that predate this page.
const List<int> _editableSections = [0, 1, 2, 3, 4, 5, 6, 7, 8, 11];

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  bool _isSaving = false;

  final _scrollController = ScrollController();
  final _sectionKeys = <int, GlobalKey>{
    for (final section in _editableSections) section: GlobalKey(),
  };

  // The draft exactly as it was when this page opened (fresh from
  // startEditMode()'s GET /profiles/draft, or whatever ProfileReviewPage was
  // already holding). Back restores this snapshot rather than leaving typed
  // values in the shared draft, so cancelling an edit never persists — not
  // even locally. The same contract ProfileWizardPage had.
  late final ProfileDraft _entryDraft;

  @override
  void initState() {
    super.initState();
    _entryDraft = ref.read(registrationProvider);
    final target = widget.initialSection;
    if (target != null && _sectionKeys.containsKey(target)) {
      // After the first layout: ensureVisible needs a laid-out render object,
      // and none of the sections have one until the page has been through a
      // frame. Every section is reachable here because the page builds them
      // all eagerly — see the Column in build().
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final sectionContext = _sectionKeys[target]?.currentContext;
        if (sectionContext == null) return;
        Scrollable.ensureVisible(
          sectionContext,
          // Leading edge of the section to the leading edge of the viewport,
          // which starts below the AppBar — so the heading lands at the top
          // of the scrollable area rather than under the chrome. `explicit`
          // makes that alignment apply even when the section is already
          // partly on screen, which the default policy would leave alone.
          alignment: 0,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // No cross-field gate here. Editing a profile is not completing a
  // registration: every field on this page is optional, and Save is always
  // available so a member can change one thing — their occupation, their
  // marital status, a single horoscope field — and persist just that
  // without first filling in sections they never opened.
  //
  // Nothing downstream needs the gate either. The section PATCH DTOs are
  // `@IsOptional()` field by field, so a partial section is a valid request
  // rather than an untraceable 400, and edit-mode save does not call
  // `POST /profiles/finalize`, which is where the end-of-signup required
  // rules actually live (and still do, unchanged, for CREATE mode).
  // Per-field *format* validation is untouched: it lives in the section
  // widgets themselves (numeric-only formatters, the name charset, the date
  // picker, `_optionalName`) and still rejects a malformed value while
  // accepting an empty one.

  /// Single source of truth for leaving without saving. The AppBar's back
  /// arrow, the bar's Back control and system/hardware back (PopScope) all
  /// call this exact method so they can never diverge: it discards whatever
  /// was typed in this session and calls no save/update API. Restoring
  /// [_entryDraft] rather than wiping the draft matters because this page is
  /// pushed on top of ProfileReviewPage — popping must leave the summary's
  /// values exactly as they were, not force a re-fetch.
  void _exitWithoutSaving() {
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

  /// Persists every section, materialized, then returns to the summary.
  Future<void> _onSave() async {
    if (_isSaving) return;
    StoryPerf.start('Save tapped');
    StoryPerf.mark('Local validation complete');

    setState(() => _isSaving = true);
    final ok = await _publish();
    if (!mounted) return;
    setState(() => _isSaving = false);
    StoryPerf.mark('Cubit/state updated (isSaving=false)');
    if (!ok) return;

    // The edit is persisted and the backend recomputed completion inside the
    // materializing PATCH. Refresh the same providers ProfileReviewPage
    // refreshes after its own save, so the summary this pops back to shows
    // the new values and percentage rather than a pre-edit snapshot.
    ref.invalidate(profileDraftResponseProvider);
    ref.invalidate(profileCompletenessSnapshotProvider);
    // discoverFeedProvider is a plain (non-autoDispose) FutureProvider kept
    // alive by the always-mounted Discover screen — invalidate it so a member
    // whose save just made them eligible does not land back on a cached
    // "INCOMPLETE_SELF_PROFILE" empty state from before this save.
    ref.invalidate(discoverFeedProvider);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).registrationProfileUpdated),
      ),
    );
    StoryPerf.mark('Navigation started (back to summary)');
    // Back to the Edit Profile summary, not out to Discover: the member
    // opened this page from there and the updated values belong in front of
    // them. The draft this page wrote into is the one the summary reads, so
    // it renders the new values on the way back with no re-fetch.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.discover);
    }
  }

  /// Reuses EDIT mode's existing whole-draft save. Returns false and shows an
  /// error snackbar on failure, leaving the member on the page with their
  /// edits intact so they can retry.
  Future<bool> _publish() async {
    try {
      await ref.read(registrationProvider.notifier).publishEditedProfile();
      StoryPerf.mark('PATCH response received');
      return true;
    } on RegistrationApiException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(
              context,
            ).registrationSaveProfileErrorDetail(e.message),
          ),
        ),
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).registrationSaveProfileError,
          ),
        ),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(registrationProvider.notifier);
    // Deliberately watches nothing: each section subscribes to its own slice
    // (see _buildSection), so a keystroke rebuilds that one section and not
    // this page's PopScope, LayoutBuilder, scroll view or bottom bar.

    // On a landscape phone the AppBar's 56dp is the difference between the
    // sticky bar fitting and overflowing (measured: 22dp over at 568x320
    // with the keyboard raised), so the title goes and Back lives on the bar
    // — which is the chrome this screen had before it was one page.
    //
    // Deliberately measured without `viewInsets`, so this depends only on the
    // device and its orientation: keyed to the usable height *with* the
    // keyboard, the AppBar would appear and vanish as the member focused and
    // blurred a field, jumping the content under their finger.
    final orientationHeight = MediaQuery.sizeOf(context).height -
        MediaQuery.paddingOf(context).vertical;
    final showAppBar = orientationHeight >= _compactChromeThreshold;

    return PopScope(
      // Back always leaves immediately, discarding this session's edits —
      // the behaviour Edit Profile has always had. No confirmation dialog,
      // because the app has never shown one here.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitWithoutSaving();
      },
      child: Scaffold(
        appBar: showAppBar
            ? AppBar(
                title: Text(l10n.drawerEditProfile),
                leading: BackButton(
                  onPressed: _isSaving ? null : _exitWithoutSaving,
                ),
              )
            : null,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Below the threshold the bar collapses to one row so the field
              // being edited and Save keep their space — a landscape phone,
              // or a portrait one with the keyboard up, cannot fit the full
              // bar.
              final compact = constraints.maxHeight < _compactChromeThreshold;
              return Column(
                children: [
                  Expanded(
                    // A Column, not a ListView: a lazy list only builds the
                    // sections inside the viewport, so on the first frame
                    // every GlobalKey below the fold still has a null
                    // context and the scroll-to-section in initState had
                    // nothing to scroll to — it silently did nothing for
                    // every section but the first. Building all ten eagerly
                    // is what makes [ProfileEditPage.initialSection] land on
                    // the right one, and this is a form whose sections are
                    // all validated and saved together anyway.
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 24),
                      // Dismiss the keyboard on scroll so a member moving
                      // between sections is not fighting it for room.
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        // Matches the full-width constraint a ListView gave
                        // its children; the Column default (center) would
                        // shrink each section to its intrinsic width.
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final section in _editableSections)
                            KeyedSubtree(
                              key: _sectionKeys[section],
                              child: _buildSection(section, notifier),
                            ),
                        ],
                      ),
                    ),
                  ),
                  RegistrationStickyBottomBar(
                    compact: compact,
                    continueLabel: l10n.actionSave,
                    continueIcon: Icons.check_rounded,
                    backLabel: l10n.registrationBack,
                    isLoading: _isSaving,
                    onBack: _isSaving ? null : _exitWithoutSaving,
                    // Always available — see the note above _exitWithoutSaving
                    // on why editing carries no required-field gate. Disabled
                    // only while a save is already in flight.
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

  /// The same section widgets the wizard built, with `scrollable: false` —
  /// this page owns the one viewport.
  ///
  /// Each section watches only its own slice of the draft. Every keystroke
  /// emits a new [ProfileDraft], but `copyWith` leaves the slices it was not
  /// given untouched, so identity comparison is enough for `select` to keep
  /// a rebuild to the one section being typed into. Watching the whole draft
  /// here would rebuild all ten on every character — cheap while a lazy list
  /// only built the visible one, not once they are all built eagerly.
  Widget _buildSection(int section, RegistrationNotifier notifier) {
    switch (section) {
      case 0:
        return Consumer(
          builder: (context, ref, _) => StepBasicInfo(
            details: ref.watch(
              registrationProvider.select((d) => d.basicDetails),
            ),
            onChanged: notifier.updateBasicDetails,
            scrollable: false,
          ),
        );
      case 1:
        return Consumer(
          builder: (context, ref, _) => StepReligion(
            details: ref.watch(
              registrationProvider.select((d) => d.religionDetails),
            ),
            onChanged: notifier.updateReligionDetails,
            scrollable: false,
          ),
        );
      case 2:
        return Consumer(
          builder: (context, ref, _) => StepLanguage(
            details: ref.watch(
              registrationProvider.select((d) => d.languageDetails),
            ),
            onChanged: notifier.updateLanguageDetails,
            scrollable: false,
          ),
        );
      case 3:
        return Consumer(
          builder: (context, ref, _) => StepLocation(
            details: ref.watch(
              registrationProvider.select((d) => d.locationDetails),
            ),
            onChanged: notifier.updateLocationDetails,
            scrollable: false,
          ),
        );
      case 4:
        return Consumer(
          builder: (context, ref, _) => StepEducation(
            details: ref.watch(
              registrationProvider.select((d) => d.educationDetails),
            ),
            onChanged: notifier.updateEducationDetails,
            scrollable: false,
          ),
        );
      case 5:
        return Consumer(
          builder: (context, ref, _) => StepPhysical(
            details: ref.watch(
              registrationProvider.select((d) => d.physicalDetails),
            ),
            onChanged: notifier.updatePhysicalDetails,
            scrollable: false,
          ),
        );
      case 6:
        return Consumer(
          builder: (context, ref, _) => StepLifestyle(
            details: ref.watch(
              registrationProvider.select((d) => d.lifestyleDetails),
            ),
            onChanged: notifier.updateLifestyleDetails,
            scrollable: false,
          ),
        );
      case 7:
        return Consumer(
          builder: (context, ref, _) => StepFamily(
            details: ref.watch(
              registrationProvider.select((d) => d.familyDetails),
            ),
            onChanged: notifier.updateFamilyDetails,
            scrollable: false,
          ),
        );
      case 8:
        return Consumer(
          builder: (context, ref, _) => StepHoroscope(
            details: ref.watch(
              registrationProvider.select((d) => d.horoscopeDetails),
            ),
            onChanged: notifier.updateHoroscopeDetails,
            scrollable: false,
          ),
        );
      case 11:
        // Photos are an independent backend resource (PhotoController), not
        // part of the draft — StepPhotos manages them directly.
        return const StepPhotos(scrollable: false);
      default:
        return const SizedBox.shrink();
    }
  }
}
