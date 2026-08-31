import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/route_names.dart';
import '../../../registration/domain/models/profile_draft.dart';
import '../../../registration/domain/models/profile_flow_mode.dart';
import '../../../registration/presentation/providers/registration_provider.dart';
import '../providers/auth_providers.dart';

/// The draft lookup is a routing decision, not a screen the user is waiting
/// on with a spinner they can cancel — a stalled request must not hold the
/// splash (or a just-tapped sign-in button) open indefinitely. Past this,
/// [PostAuthDestination] falls back rather than waits.
const Duration _draftLookupTimeout = Duration(seconds: 6);

/// A Firebase account whose creation and last-sign-in timestamps are this
/// close together has never signed in before — this *is* the sign-up.
/// Used only to pick a safe fallback when the backend can't be reached.
const Duration _brandNewAccountWindow = Duration(minutes: 2);

/// Where an authenticated user belongs, in one place.
///
/// Every path that completes authentication asks this the same question:
/// email/password login, Google sign-in, phone OTP, and the splash's cold
/// start. Before this existed each of them hardcoded its own answer
/// ("Discover" for login, "registration wizard" for OTP), which is why a
/// half-registered user could land in Discover with no profile and a
/// brand-new Google user never saw the registration flow at all.
///
/// The order of precedence is:
/// 1. Not signed in → the sign-up landing screen.
/// 2. Has an email address that isn't verified yet → the verify-email step.
/// 3. Backend profile draft says complete → Discover.
/// 4. No "profile is for" choice recorded (the value is empty, which is
///    what a draft the user has never answered actually holds) →
///    [RouteNames.createProfileFor].
/// 5. Otherwise → resume the wizard at the step the backend last saved.
///
/// Never throws. A backend that can't be reached falls back to Discover for
/// an established account (which is where it always used to send them) and
/// to the "profile is for" step for an account created moments ago — that
/// user has no profile to show, so Discover would be an empty dead end.
class PostAuthDestination {
  PostAuthDestination(this._ref);

  final Ref _ref;

  Future<String> resolve() async {
    final user = _ref.read(firebaseAuthServiceProvider).currentUser;
    if (user == null) return RouteNames.registrationLanding;

    // Phone-only accounts have no address to verify, so this gate must key
    // on "has an email that is unverified", not on `emailVerified` alone —
    // otherwise a phone signup loops forever on a verify-email screen with
    // nothing to resend to.
    final email = user.email;
    if (email != null && email.isNotEmpty && !user.emailVerified) {
      return RouteNames.verifyEmail;
    }

    final Map<String, dynamic> draft;
    try {
      draft = await _ref
          .read(registrationRepositoryProvider)
          .getDraft()
          .timeout(_draftLookupTimeout);
    } catch (_) {
      return _isBrandNewAccount(user.metadata.creationTime,
              user.metadata.lastSignInTime)
          ? RouteNames.createProfileFor
          : RouteNames.discover;
    }

    // A finished profile is never sent back through registration — and the
    // backend cannot call a profile complete without a profileCreatedFor,
    // so this can't swallow an unanswered one.
    if (draft['isComplete'] == true) return RouteNames.discover;

    final restored = ProfileDraft.fromJson(draft);

    // The gate this whole screen order exists for: an empty value means the
    // question has genuinely never been answered (BasicDetails documents why
    // the field has no default), so the user goes to CreateProfileForPage —
    // never straight into the wizard, and never into Discover.
    if (restored.basicDetails.profileCreatedFor.trim().isEmpty) {
      return RouteNames.createProfileFor;
    }

    // Mid-registration: rehydrate the wizard from the backend's own copy so
    // the user resumes on the step they left, with the answers they already
    // gave, rather than restarting at step 0. This is the resume path for a
    // device that lost its local snapshot (reinstall, new phone, or a
    // process kill before the debounced save landed).
    final step = (draft['currentStep'] as num?)?.toInt() ?? restored.currentStep;
    _ref.read(registrationProvider.notifier).restore(
          restored.copyWith(currentStep: step.clamp(0, ProfileDraft.totalSteps - 1)),
          ProfileFlowMode.create,
        );
    return RouteNames.registrationWizard;
  }

  bool _isBrandNewAccount(DateTime? createdAt, DateTime? lastSignInAt) {
    if (createdAt == null || lastSignInAt == null) return false;
    return lastSignInAt.difference(createdAt).abs() < _brandNewAccountWindow;
  }
}

final postAuthDestinationProvider = Provider<PostAuthDestination>(
  PostAuthDestination.new,
);
