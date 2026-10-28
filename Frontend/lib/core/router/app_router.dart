import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/astro/presentation/pages/horoscope_matching_page.dart';
import '../../features/authentication/presentation/pages/email_verify_screen.dart';
import '../../features/authentication/presentation/pages/forgot_password_page.dart';
import '../../features/authentication/presentation/pages/login_otp_screen.dart';
import '../../features/authentication/presentation/pages/login_page.dart';
import '../../features/authentication/presentation/pages/otp_page.dart';
import '../../features/authentication/presentation/pages/phone_verify_screen.dart';
import '../../features/authentication/presentation/pages/registration_landing_page.dart';
import '../../features/discover/domain/entities/discovery_profile_entity.dart';
import 'profile_navigation.dart';
import 'route_entity_pages.dart';
import '../../features/discover/presentation/pages/discover_page.dart';
import '../../features/help/presentation/pages/help_page.dart';
import '../../features/help/presentation/pages/partner_program_help_page.dart';
import '../../features/support/domain/models/support_ticket.dart';
import '../../features/support/presentation/pages/support_ticket_form_page.dart';
import '../../features/support/presentation/pages/ticket_history_page.dart';
import '../../features/inbox/domain/entities/conversation_entity.dart';
import '../../features/inbox/presentation/pages/inbox_shell_page.dart';
import '../../features/interests/presentation/pages/interests_received_page.dart';
import '../../features/interests/presentation/pages/interests_sent_page.dart';
import '../../features/language/presentation/pages/language_page.dart';
import '../../features/matches/presentation/pages/matches_page.dart';
import '../../features/nearby/presentation/pages/nearby_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_page.dart';
import '../../features/partner_preferences/presentation/pages/partner_preferences_page.dart';
import '../../features/membership/presentation/pages/membership_history_page.dart';
import '../../features/premium/presentation/pages/premium_page.dart';
import '../../features/privacy/presentation/pages/privacy_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/profile_detail/presentation/pages/profile_detail_page.dart';
import '../../features/profile_menu/presentation/pages/profile_menu_page.dart';
import '../../features/profile_views/presentation/pages/profile_viewers_page.dart';
import '../../features/profile_completion/presentation/pages/profile_completion_page.dart';
import '../../features/psychology/presentation/pages/psychology_quiz_page.dart';
import '../../features/registration/presentation/pages/create_profile_for_page.dart';
import '../../features/registration/presentation/pages/onboarding_about_page.dart';
import '../../features/registration/presentation/pages/onboarding_contact_page.dart';
import '../../features/registration/presentation/pages/onboarding_education_page.dart';
import '../../features/registration/presentation/pages/onboarding_income_page.dart';
import '../../features/registration/presentation/pages/onboarding_marital_page.dart';
import '../../features/registration/presentation/pages/onboarding_photos_page.dart';
import '../../features/registration/presentation/pages/onboarding_name_page.dart';
import '../../features/registration/presentation/pages/onboarding_religion_page.dart';
import '../../features/registration/presentation/pages/onboarding_verify_mobile_page.dart';
import '../../features/registration/presentation/pages/profile_basics_page.dart';
import '../../features/registration/presentation/pages/profile_review_page.dart';
import '../../features/registration/presentation/pages/edit_profile_page.dart';
import '../../features/registration/presentation/pages/profile_section_edit_page.dart';
import '../../features/registration/presentation/pages/registration_completing_page.dart';
import '../../features/registration/presentation/pages/registration_page.dart';
import '../../features/registration/presentation/pages/registration_success_page.dart';
import '../../features/registration/presentation/pages/registration_welcome_page.dart';
import '../../features/search/presentation/pages/search_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/shortlist/presentation/pages/shortlisted_page.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../../features/subscription/presentation/pages/subscription_page.dart';
import '../../features/verification/presentation/pages/verification_page.dart';
import '../../features/verification/presentation/pages/face_verification_page.dart';
import '../../features/authentication/domain/services/local_auth_session.dart';
import '../../features/authentication/presentation/providers/auth_providers.dart';
import '../../features/authentication/presentation/utils/post_auth_destination.dart';
import '../services/storage_service.dart';
import '../widgets/navigation/app_bottom_nav.dart';
import 'auth_return_location.dart';
import 'route_names.dart';

/// Nenjam Matrimony — GoRouter Configuration
///
/// Defines all app routes with:
/// - Shell route for bottom navigation
/// - Smooth page transitions
/// - Named routes for type-safe navigation
///
/// [createRouter] must be called exactly once and the resulting [GoRouter]
/// instance kept alive for the app's lifetime (see `main.dart`'s
/// `late final router = createRouter(ref);`). Calling it again would build a
/// second [GoRouter] that reuses [rootNavigatorKey] — two Navigators can't
/// share one GlobalKey — and would silently drop the entire in-memory
/// navigation stack (back to `initialLocation`), which looks exactly like
/// "the app forgot where I was" even though the process never died.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

GoRouter? _appRouter;

/// The one [GoRouter] [createRouter] built, reachable without a
/// [BuildContext].
///
/// Services must never touch [Navigator] directly, but a push-notification
/// tap has no context of its own — on a cold start from a terminated app the
/// widget tree may not exist yet when `getInitialMessage()` resolves, and
/// `rootNavigatorKey.currentContext` is still null at that point. Routing
/// through the router instance keeps every navigation going through
/// GoRouter's named routes while remaining callable from a plain service
/// (see `NotificationNavigationService`).
///
/// Null only before [createRouter] has run — i.e. before `main.dart` builds
/// the app. Callers must handle that (queue the intent) rather than assume.
GoRouter? get appRouterOrNull => _appRouter;

/// Adapts a [Stream] into a [Listenable] so GoRouter's [GoRouter.refresh]
/// fires — and `redirect` re-runs — on every event, not just on explicit
/// navigation. go_router shipped this itself pre-6.0; since then it's the
/// documented pattern to copy into the app (see go_router's "Multiple
/// Navigators" guide).
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((event) {
      notifyListeners();
    });
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Builds the app's [GoRouter], gating every route not listed in
/// [RouteNames.publicRoutes] behind an active Firebase session AND, once
/// signed in, behind [PostAuthDestination] agreeing onboarding is either
/// finished or not the reason this particular route was requested.
///
/// [redirect] is the single source of truth for route protection — it runs
/// for every navigation, including deep links and links restored from a
/// previous process, so a protected path can never be reached by typing a
/// URL, tapping a deep link, or hot-restoring navigation state. It awaits
/// [authStateChangesProvider]'s first emission (Firebase's own session
/// restoration signal) rather than reading `currentUser` synchronously, so
/// it never races a session that's still being restored.
///
/// The onboarding half defers entirely to [PostAuthDestination.resolve] —
/// the same resolver splash/login/verify screens already call — rather than
/// restating its gate chain: this guard only decides *whether* to ask it
/// (skipped once [StorageService.onboardingCompleted] is locally true, so a
/// finished member's ordinary navigation never pays for the network calls
/// `resolve()` can make) and *whether* its answer is a real block (only a
/// [RouteNames.publicRoutes] destination is — see the inline comment at the
/// call site for why `RouteNames.discover` specifically is not).
///
/// [refreshListenable] re-runs that redirect whenever the Firebase auth
/// stream emits — e.g. a background 401 recovery (see api_providers.dart)
/// or a logout triggered from anywhere in the app — so the user is bounced
/// to Login automatically without every call site needing its own
/// navigation logic.
/// Whether this device finished the new signup onboarding. Guarded: local
/// storage may not be initialised when a redirect runs very early, and
/// "cannot tell" must mean "not signed in", never a crash in the router.
bool _onboardingCompletedLocally() {
  try {
    return storageService.onboardingCompleted;
  } catch (_) {
    return false;
  }
}

/// Whether a signed-out visitor is nonetheless allowed into the app.
///
/// Two development bridges, both paired with the static OTP verifier and
/// both deleted with it:
///
///  * signup collects a whole profile before asking for a credential, so a
///    member who finished onboarding has no session and would otherwise be
///    bounced back to the landing screen from the last step
///    ([StorageService.onboardingCompleted]);
///  * mobile login — by OTP or by password — cannot mint a Firebase session
///    either, and records a [LocalAuthSession] instead.
///
/// Neither proves identity. Both exist only so a user the product considers
/// logged in is not treated as signed out by the guard.
bool _signedInLocally() =>
    _onboardingCompletedLocally() || hasLocalAuthSession();

GoRouter createRouter(WidgetRef ref) {
  // On the web, make a pushed route (profile, chat, settings, ...) show up in
  // the address bar. By default only go() does, so refreshing a pushed page
  // reloaded whichever tab it was opened from. Native builds have no URL, so
  // they are left exactly as they were.
  if (kIsWeb) GoRouter.optionURLReflectsImperativeAPIs = true;

  // Whether anyone has been signed in since the app started. Tells a visitor
  // who arrived signed out (a link to remember for after login) from one who
  // just signed out (whose page must not become the next login's
  // destination) — see AuthReturnLocation.
  var hadSession = false;

  return _appRouter = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: RouteNames.splash,
    refreshListenable: GoRouterRefreshStream(
      ref.read(authRepositoryProvider).authStateChanges(),
    ),
    redirect: (context, state) async {
      // NB: never call GoRouter.of(context) / read routerDelegate here — the
      // redirect's `context` is NOT under the GoRouter InheritedWidget during
      // initial resolution or a refreshListenable firing (e.g. sign-out),
      // which throws "No GoRouter found in context". Everything routing
      // decisions need is already on `state`.
      final location = state.matchedLocation;
      if (RouteNames.publicRoutes.contains(location)) {
        return null;
      }

      final user = await ref.read(authStateChangesProvider.future);
      if (user == null && !_signedInLocally()) {
        if (hadSession) {
          AuthReturnLocation.clear();
        } else {
          AuthReturnLocation.remember(state.uri.toString());
        }
        // The landing screen, not Login: a signed-out visitor is far more
        // often someone who has never had an account than someone whose
        // session lapsed, and Login is one tap away from there anyway.
        return RouteNames.registrationLanding;
      }
      hadSession = true;

      // Signed in (Firebase or a development bridge — see _signedInLocally)
      // and asking for a protected, non-onboarding route (every onboarding
      // screen is in publicRoutes and returned above already). Being signed
      // in only proves identity, not that onboarding finished, and until now
      // nothing here checked the second thing: PostAuthDestination — the
      // resolver that actually knows which onboarding step (if any) is still
      // owed — was only ever invoked from specific screens (splash, login,
      // phone/email verify), never from this guard. A deep link, a restored
      // nav state, or any programmatic `context.go` to e.g. Discover that
      // skipped those screens reached it anyway, with no onboarding gate at
      // all.
      //
      // onboardingCompleted is the same local, no-network flag the dev
      // bridges above already read — checked first so a member who has
      // already finished (the overwhelming majority of navigations) never
      // pays for a draft/profile fetch just to reconfirm what is already
      // known. Only an incomplete-or-unknown device asks the resolver.
      if (!_onboardingCompletedLocally()) {
        final destination = await ref
            .read(postAuthDestinationProvider)
            .resolve();
        // Only a public route (an onboarding step, or verifyEmail — every
        // real gate PostAuthDestination guards with) is a genuine block.
        // RouteNames.discover, the one non-public route it can return, means
        // "onboarding is done" — and PostAuthDestination.resolve() never
        // targets any other protected route (Settings, Profile, Edit
        // Profile, ...), so seeing anything besides an onboarding gate here
        // means this device's local onboardingCompleted flag just has not
        // caught up yet (a second device, a reinstall, a stale flag from
        // before finalize ran) while the account itself is fine — and the
        // originally requested route is legitimate. Redirecting on that
        // would wrongly bounce an already-finished member away from a real
        // destination, which is exactly what the EDIT/profile flows this fix
        // must not disturb depend on not happening.
        if (RouteNames.publicRoutes.contains(destination) &&
            destination != location) {
          return destination;
        }
      }

      return null;
    },
    routes: [
      // ─── Standalone Routes (no bottom nav) ────────────────────
      GoRoute(
        path: RouteNames.splash,
        name: RouteNames.splashName,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: RouteNames.language,
        name: RouteNames.languageName,
        builder: (context, state) => const LanguagePage(),
      ),
      // The sign-up landing screen replaced the old auth-selection hub, but
      // the path outlived it — a deep link, a saved shortcut, or a session
      // restored from before the rename can still ask for it. Redirecting
      // (rather than keeping a second landing screen alive) means there is
      // exactly one implementation to maintain.
      GoRoute(
        path: RouteNames.authSelection,
        name: RouteNames.authSelectionName,
        redirect: (context, state) => RouteNames.registrationLanding,
      ),
      GoRoute(
        path: RouteNames.registrationLanding,
        name: RouteNames.registrationLandingName,
        builder: (context, state) => const RegistrationLandingPage(),
      ),
      GoRoute(
        path: RouteNames.onboarding,
        name: RouteNames.onboardingName,
        builder: (context, state) => const OnboardingPage(),
      ),
      // The login form is the login screen, and `/login` is the path four
      // other screens (Settings, Verify Email, the Email + Mobile step, the
      // landing screen) already mean when they say "send them to log in".
      // Redirecting rather than mounting the page twice means there is
      // exactly one login route to reason about, and no call site had to
      // change to stop going through the removed Welcome Back screen.
      GoRoute(
        path: RouteNames.login,
        name: RouteNames.loginName,
        redirect: (context, state) => RouteNames.loginForm,
      ),
      GoRoute(
        path: RouteNames.loginForm,
        name: RouteNames.loginFormName,
        builder: (context, state) {
          final extra = state.extra;
          LoginFormMode mode = LoginFormMode.mobileOtp;
          if (extra is Map) {
            // Which credential the form opens on. Absent means the mobile
            // channel it has always opened on.
            final modeName = extra['mode'];
            if (modeName is String) {
              for (final value in LoginFormMode.values) {
                if (value.name == modeName) mode = value;
              }
            }
          }
          return LoginPage(mode: mode);
        },
      ),
      GoRoute(
        path: RouteNames.otp,
        name: RouteNames.otpName,
        builder: (context, state) => const OtpPage(),
      ),
      GoRoute(
        path: RouteNames.loginOtp,
        name: RouteNames.loginOtpName,
        builder: (context, state) => const LoginOtpScreen(),
      ),
      GoRoute(
        path: RouteNames.verifyEmail,
        name: RouteNames.verifyEmailName,
        builder: (context, state) => const EmailVerifyScreen(),
      ),
      GoRoute(
        path: RouteNames.verifyPhone,
        name: RouteNames.verifyPhoneName,
        builder: (context, state) => const PhoneVerifyScreen(),
      ),
      GoRoute(
        path: RouteNames.forgotPassword,
        name: RouteNames.forgotPasswordName,
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: RouteNames.registration,
        name: RouteNames.registrationName,
        builder: (context, state) => const RegistrationPage(),
      ),
      GoRoute(
        path: RouteNames.createProfileFor,
        name: RouteNames.createProfileForName,
        builder: (context, state) => const CreateProfileForPage(),
      ),
      GoRoute(
        path: RouteNames.onboardingNameDob,
        name: RouteNames.onboardingNameDobName,
        builder: (context, state) => const OnboardingNamePage(),
      ),
      GoRoute(
        path: RouteNames.onboardingReligion,
        name: RouteNames.onboardingReligionName,
        builder: (context, state) => const OnboardingReligionPage(),
      ),
      GoRoute(
        path: RouteNames.onboardingContact,
        name: RouteNames.onboardingContactName,
        builder: (context, state) => const OnboardingContactPage(),
      ),
      GoRoute(
        path: RouteNames.profileBasics,
        name: RouteNames.profileBasicsName,
        builder: (context, state) => const ProfileBasicsPage(),
      ),
      GoRoute(
        path: RouteNames.onboardingMarital,
        name: RouteNames.onboardingMaritalName,
        builder: (context, state) => const OnboardingMaritalPage(),
      ),
      GoRoute(
        path: RouteNames.onboardingEducation,
        name: RouteNames.onboardingEducationName,
        builder: (context, state) => const OnboardingEducationPage(),
      ),
      GoRoute(
        path: RouteNames.onboardingIncome,
        name: RouteNames.onboardingIncomeName,
        builder: (context, state) => const OnboardingIncomePage(),
      ),
      GoRoute(
        path: RouteNames.onboardingPhotos,
        name: RouteNames.onboardingPhotosName,
        builder: (context, state) => const OnboardingPhotosPage(),
      ),
      GoRoute(
        path: RouteNames.onboardingAbout,
        name: RouteNames.onboardingAboutName,
        builder: (context, state) => const OnboardingAboutPage(),
      ),
      GoRoute(
        path: RouteNames.onboardingVerifyMobile,
        name: RouteNames.onboardingVerifyMobileName,
        builder: (context, state) => const OnboardingVerifyMobilePage(),
      ),
      GoRoute(
        path: RouteNames.registrationWelcome,
        name: RouteNames.registrationWelcomeName,
        builder: (context, state) => const RegistrationWelcomePage(),
      ),
      // ─── Edit Profile ───────────────────────────────────────────
      //
      // A section list, and one edit page per section that saves only that
      // section — see profileSectionRoute(). Family and horoscope are
      // separate profile sections, reached from the Profile screen. None of
      // these is in RouteNames.publicRoutes, so all require a signed-in
      // member.
      GoRoute(
        path: RouteNames.editProfile,
        name: RouteNames.editProfileName,
        builder: (context, state) => const EditProfilePage(),
      ),
      GoRoute(
        path: RouteNames.basicInfoEdit,
        name: RouteNames.basicInfoEditName,
        builder: (context, state) => const BasicInfoEditPage(),
      ),
      GoRoute(
        path: RouteNames.religionCommunityEdit,
        name: RouteNames.religionCommunityEditName,
        builder: (context, state) => const ReligionCommunityEditPage(),
      ),
      GoRoute(
        path: RouteNames.locationEdit,
        name: RouteNames.locationEditName,
        builder: (context, state) => const LocationEditPage(),
      ),
      GoRoute(
        path: RouteNames.educationWorkEdit,
        name: RouteNames.educationWorkEditName,
        builder: (context, state) => const EducationWorkEditPage(),
      ),
      GoRoute(
        path: RouteNames.physicalDetailsEdit,
        name: RouteNames.physicalDetailsEditName,
        builder: (context, state) => const PhysicalDetailsEditPage(),
      ),
      GoRoute(
        path: RouteNames.lifestyleAboutEdit,
        name: RouteNames.lifestyleAboutEditName,
        builder: (context, state) => const LifestyleAboutEditPage(),
      ),
      GoRoute(
        path: RouteNames.photosEdit,
        name: RouteNames.photosEditName,
        builder: (context, state) => const PhotosEditPage(),
      ),
      GoRoute(
        path: RouteNames.familyDetailsEdit,
        name: RouteNames.familyDetailsEditName,
        builder: (context, state) => const FamilyDetailsEditPage(),
      ),
      GoRoute(
        path: RouteNames.horoscopeDetailsEdit,
        name: RouteNames.horoscopeDetailsEditName,
        builder: (context, state) => const HoroscopeDetailsEditPage(),
      ),
      GoRoute(
        path: RouteNames.registrationCompleting,
        name: RouteNames.registrationCompletingName,
        builder: (context, state) => const RegistrationCompletingPage(),
      ),
      GoRoute(
        path: RouteNames.registrationSuccess,
        name: RouteNames.registrationSuccessName,
        builder: (context, state) => const RegistrationSuccessPage(),
      ),
      GoRoute(
        path: RouteNames.psychologyQuiz,
        name: RouteNames.psychologyQuizName,
        builder: (context, state) => const PsychologyQuizPage(),
      ),
      // ─── Relationship Intelligence (independent of registration) ──
      GoRoute(
        path: RouteNames.horoscopeMatching,
        name: RouteNames.horoscopeMatchingName,
        builder: (context, state) => const HoroscopeMatchingPage(),
      ),
      GoRoute(
        path: RouteNames.profileReview,
        name: RouteNames.profileReviewName,
        builder: (context, state) => const ProfileReviewPage(),
      ),
      GoRoute(
        path: RouteNames.profileCompletion,
        name: RouteNames.profileCompletionName,
        builder: (context, state) => const ProfileCompletionPage(),
      ),
      GoRoute(
        path: RouteNames.settings,
        name: RouteNames.settingsName,
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: RouteNames.verification,
        name: RouteNames.verificationName,
        builder: (context, state) => const VerificationPage(),
      ),
      GoRoute(
        path: RouteNames.faceVerification,
        name: RouteNames.faceVerificationName,
        builder: (context, state) => const FaceVerificationPage(),
      ),
      GoRoute(
        path: RouteNames.membershipHistory,
        name: RouteNames.membershipHistoryName,
        builder: (context, state) => const MembershipHistoryPage(),
      ),
      GoRoute(
        path: RouteNames.subscription,
        name: RouteNames.subscriptionName,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SubscriptionPage(),
          transitionsBuilder: _slideUpTransition,
        ),
      ),
      GoRoute(
        path: RouteNames.help,
        name: RouteNames.helpName,
        builder: (context, state) => const HelpPage(),
      ),
      GoRoute(
        path: RouteNames.supportTicketForm,
        name: RouteNames.supportTicketFormName,
        builder: (context, state) => SupportTicketFormPage(
          type:
              state.extra as SupportTicketType? ??
              SupportTicketType.contactSupport,
        ),
      ),
      GoRoute(
        path: RouteNames.ticketHistory,
        name: RouteNames.ticketHistoryName,
        builder: (context, state) => const TicketHistoryPage(),
      ),
      GoRoute(
        path: RouteNames.partnerProgramHelp,
        name: RouteNames.partnerProgramHelpName,
        builder: (context, state) => const PartnerProgramHelpPage(),
      ),
      GoRoute(
        path: RouteNames.privacy,
        name: RouteNames.privacyName,
        builder: (context, state) => const PrivacyPage(),
      ),
      GoRoute(
        path: RouteNames.partnerPreferences,
        name: RouteNames.partnerPreferencesName,
        builder: (context, state) => const PartnerPreferencesPage(),
      ),
      GoRoute(
        path: RouteNames.interestsSent,
        name: RouteNames.interestsSentName,
        builder: (context, state) => const InterestsSentPage(),
      ),
      GoRoute(
        path: RouteNames.interestsReceived,
        name: RouteNames.interestsReceivedName,
        builder: (context, state) => const InterestsReceivedPage(),
      ),
      GoRoute(
        path: RouteNames.shortlisted,
        name: RouteNames.shortlistedName,
        builder: (context, state) => const ShortlistedPage(),
      ),
      GoRoute(
        // Pushed full-screen (from the drawer's Near Me item and from the
        // Matches "Near Me" chip), not a bottom-nav branch: it has its own
        // AppBar and Back, and the four StatefulShellRoute branches below
        // are the four tabs the bottom bar actually renders.
        path: RouteNames.nearby,
        name: RouteNames.nearbyName,
        builder: (context, state) => const NearbyPage(),
      ),
      GoRoute(
        path: RouteNames.profileViewers,
        name: RouteNames.profileViewersName,
        // `?openedFromNotification=true` is set only by
        // NotificationNavigationService; the drawer pushes the bare path.
        // It decides where Back goes if this page ends up with nothing
        // beneath it — see ProfileViewersPage's doc comment.
        builder: (context, state) => ProfileViewersPage(
          openedFromNotification:
              state.uri.queryParameters[RouteNames
                  .openedFromNotificationParam] ==
              'true',
        ),
      ),
      GoRoute(
        path: RouteNames.profileDetailPattern,
        name: RouteNames.profileDetailName,
        // pageBuilder (not builder) so this route's Page can carry its
        // own unique `key:` — see ProfileDetailArgs.pageKey's doc comment
        // for why go_router's default `state.pageKey` isn't safe here:
        // this static, extra-carrying path is reachable recursively
        // (Profile Detail's own Similar Profiles shelf pushes it again),
        // so two simultaneously-mounted instances need distinct keys or
        // Flutter's Navigator throws '!keyReservation.contains(key)'.
        pageBuilder: (context, state) {
          final extra = state.extra;
          // Accepts a bare DiscoveryProfileEntity too (not just
          // ProfileDetailArgs) — defensive backward compatibility for
          // any call site that pushes this route directly rather than
          // through `openProfileDetail`.
          final args = switch (extra) {
            final ProfileDetailArgs a => a,
            final DiscoveryProfileEntity p => ProfileDetailArgs(p),
            _ => null,
          };
          if (args == null) {
            // A reload, copied link or bookmark: the URL names the profile
            // but there is no in-memory entity. Look it up by id, with
            // loading / not-available / retry states.
            return MaterialPage<void>(
              key: state.pageKey,
              child: ProfileDetailRoutePage(
                profileId: state.pathParameters['profileId']!,
              ),
            );
          }
          return MaterialPage<void>(
            key: args.pageKey,
            name: state.name ?? state.path,
            restorationId: args.pageKey.value,
            child: ProfileDetailPage(
              profile: args.profile,
              heroTag: args.heroTag,
              isBlocked: args.isBlocked,
            ),
          );
        },
      ),
      GoRoute(
        path: RouteNames.chatDetailPattern,
        name: RouteNames.chatDetailName,
        builder: (context, state) => InboxShellPage(
          selectedConversationId: state.pathParameters['conversationId']!,
          // Present for in-app navigation; absent after a reload or for a
          // copied link, in which case the page looks the thread up by id.
          initialConversation: state.extra is ConversationEntity
              ? state.extra! as ConversationEntity
              : null,
        ),
      ),
      // Search, Notifications and Profile are *reached from* the bottom-nav
      // branches (and, for Search, from more than one branch — Discover's
      // AppBar and Matches' category bar both push it) but aren't branch
      // roots themselves. Standalone routes push onto the root navigator,
      // covering the whole shell — the same "temporary page" pattern as
      // Settings/Verification/etc. below — rather than belonging to any
      // one branch's own stack, which is what a route pushed from
      // multiple different branches needs.
      GoRoute(
        path: RouteNames.search,
        name: RouteNames.searchName,
        builder: (context, state) => const SearchPage(),
      ),
      GoRoute(
        path: RouteNames.notifications,
        name: RouteNames.notificationsName,
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: RouteNames.profile,
        name: RouteNames.profileName,
        builder: (context, state) => const ProfilePage(),
      ),
      // The profile/account menu. A root-navigator route (not a Drawer on
      // Discover's Scaffold, which is what it used to be) so it covers the
      // whole StatefulShellRoute — no sliver of Discover beside it, and no
      // floating bottom-nav pill over it, since both belong to the shell
      // underneath. A plain `builder:` gives it the default platform page
      // transition, which is what carries the iOS back-swipe.
      GoRoute(
        path: RouteNames.profileMenu,
        name: RouteNames.profileMenuName,
        builder: (context, state) => const ProfileMenuPage(),
      ),

      // ─── Bottom Navigation — StatefulShellRoute ────────────────
      //
      // Each branch owns its own Navigator and route stack, preserved by
      // an IndexedStack under the hood: switching Discover → Matches →
      // Discover restores Discover's scroll position and any state
      // exactly as left, which a plain ShellRoute (a single Navigator
      // shared across all tabs, rebuilt on every switch) cannot do.
      // AppBottomNavShell's PopScope still owns "Back on any non-Discover
      // branch returns to Discover" — StatefulShellRoute doesn't impose
      // that policy itself, it just gives each branch a real stack to
      // reason about.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppBottomNavShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.discover,
                name: RouteNames.discoverName,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: DiscoverPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.matches,
                name: RouteNames.matchesName,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: MatchesPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.messages,
                name: RouteNames.messagesName,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: InboxShellPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.premium,
                name: RouteNames.premiumName,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: PremiumPage()),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

// ─── Custom Transitions ────────────────────────────────────────────

Widget _slideUpTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return SlideTransition(
    position: Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
    child: child,
  );
}
