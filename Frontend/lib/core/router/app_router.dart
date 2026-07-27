import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/astro/presentation/pages/horoscope_matching_page.dart';
import '../../features/authentication/presentation/pages/auth_selection_page.dart';
import '../../features/authentication/presentation/pages/email_verify_screen.dart';
import '../../features/authentication/presentation/pages/forgot_password_page.dart';
import '../../features/authentication/presentation/pages/login_otp_screen.dart';
import '../../features/authentication/presentation/pages/login_page.dart';
import '../../features/authentication/presentation/pages/otp_page.dart';
import '../../features/authentication/presentation/pages/phone_verify_screen.dart';
import '../../features/discover/domain/entities/discovery_profile_entity.dart';
import 'profile_navigation.dart';
import '../../features/discover/presentation/pages/discover_page.dart';
import '../../features/help/presentation/pages/help_page.dart';
import '../../features/inbox/domain/entities/conversation_entity.dart';
import '../../features/inbox/presentation/pages/chat_detail_page.dart';
import '../../features/inbox/presentation/pages/inbox_page.dart';
import '../../features/interests/presentation/pages/interests_received_page.dart';
import '../../features/interests/presentation/pages/interests_sent_page.dart';
import '../../features/language/presentation/pages/language_page.dart';
import '../../features/matches/presentation/pages/matches_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_page.dart';
import '../../features/partner_preferences/presentation/pages/partner_preferences_page.dart';
import '../../features/premium/presentation/pages/premium_page.dart';
import '../../features/privacy/presentation/pages/privacy_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/profile_detail/presentation/pages/profile_detail_page.dart';
import '../../features/profile_intelligence/presentation/pages/profile_intelligence_page.dart';
import '../../features/profile_prompts/domain/models/prompt_bank_item.dart';
import '../../features/profile_prompts/presentation/pages/choose_prompt_page.dart';
import '../../features/profile_completion/presentation/pages/profile_completion_page.dart';
import '../../features/psychology/presentation/pages/psychology_quiz_page.dart';
import '../../features/registration/presentation/pages/create_profile_for_page.dart';
import '../../features/registration/presentation/pages/profile_review_page.dart';
import '../../features/registration/presentation/pages/profile_wizard_page.dart';
import '../../features/registration/presentation/pages/registration_completing_page.dart';
import '../../features/registration/presentation/pages/registration_page.dart';
import '../../features/registration/presentation/pages/registration_success_page.dart';
import '../../features/registration/presentation/pages/registration_welcome_page.dart';
import '../../features/search/presentation/pages/search_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/shortlist/presentation/pages/shortlisted_page.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../../features/subscription/presentation/pages/subscription_page.dart';
import '../../features/trust_score/presentation/pages/trust_score_page.dart';
import '../../features/verification/presentation/pages/verification_page.dart';
import '../../features/visitors/presentation/pages/visitors_page.dart';
import '../../features/authentication/presentation/providers/auth_providers.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/navigation/app_bottom_nav.dart';
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
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

// TEMP DEBUG — remove before shipping.
//
// Logs every didPush/didPop/didRemove/didReplace on whichever Navigator
// it's attached to, tagged with [label] so root-vs-branch is unambiguous
// in the console.
class _DebugNavObserver extends NavigatorObserver {
  _DebugNavObserver(this.label);
  final String label;

  // `route.settings` for a go_router (Page-API) route IS the Page itself
  // (`Page<T> extends RouteSettings`), so this recovers the exact
  // `Page.key` that `Navigator._debugCheckDuplicatedPageKeys` checks for
  // duplicates — printing it here surfaces the actual colliding key the
  // next time `!keyReservation.contains(key)` fires, since that assertion's
  // own message never includes it.
  String _name(Route<dynamic>? r) {
    final settings = r?.settings;
    final name = settings?.name ?? settings?.toString() ?? 'null';
    final key = settings is Page ? settings.key : null;
    return key == null ? name : '$name [key=$key]';
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('[NAV:$label] didPush  ${_name(previousRoute)} -> ${_name(route)}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('[NAV:$label] didPop   ${_name(route)} -> ${_name(previousRoute)}');
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    debugPrint('[NAV:$label] didRemove ${_name(route)} -> ${_name(previousRoute)}');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    debugPrint('[NAV:$label] didReplace ${_name(oldRoute)} -> ${_name(newRoute)}');
  }
}

/// Adapts a [Stream] into a [Listenable] so GoRouter's [GoRouter.refresh]
/// fires — and `redirect` re-runs — on every event, not just on explicit
/// navigation. go_router shipped this itself pre-6.0; since then it's the
/// documented pattern to copy into the app (see go_router's "Multiple
/// Navigators" guide).
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Builds the app's [GoRouter], gating every route not listed in
/// [RouteNames.publicRoutes] behind an active Firebase session.
///
/// [redirect] is the single source of truth for route protection — it runs
/// for every navigation, including deep links and links restored from a
/// previous process, so a protected path can never be reached by typing a
/// URL, tapping a deep link, or hot-restoring navigation state. It awaits
/// [authStateChangesProvider]'s first emission (Firebase's own session
/// restoration signal) rather than reading `currentUser` synchronously, so
/// it never races a session that's still being restored.
///
/// [refreshListenable] re-runs that redirect whenever the Firebase auth
/// stream emits — e.g. a background 401 recovery (see api_providers.dart)
/// or a logout triggered from anywhere in the app — so the user is bounced
/// to Login automatically without every call site needing its own
/// navigation logic.
GoRouter createRouter(WidgetRef ref) {
  return GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: RouteNames.splash,
      debugLogDiagnostics: true,
      // TEMP DEBUG — remove before shipping.
      observers: [_DebugNavObserver('root')],
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
        if (RouteNames.publicRoutes.contains(location)) return null;

        final user = await ref.read(authStateChangesProvider.future);
        if (user == null) return RouteNames.login;
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
        GoRoute(
          path: RouteNames.authSelection,
          name: RouteNames.authSelectionName,
          builder: (context, state) => const AuthSelectionPage(),
        ),
        GoRoute(
          path: RouteNames.onboarding,
          name: RouteNames.onboardingName,
          builder: (context, state) => const OnboardingPage(),
        ),
        GoRoute(
          path: RouteNames.login,
          name: RouteNames.loginName,
          builder: (context, state) {
            final extra = state.extra;
            int initialTab = 0;
            if (extra is Map) {
              if (extra['tab'] is int) {
                initialTab = extra['tab'] as int;
              } else if (extra['initialTab'] is int) {
                initialTab = extra['initialTab'] as int;
              }
            }
            return LoginPage(initialTab: initialTab);
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
          path: RouteNames.registrationWelcome,
          name: RouteNames.registrationWelcomeName,
          builder: (context, state) => const RegistrationWelcomePage(),
        ),
        GoRoute(
          path: RouteNames.registrationWizard,
          name: RouteNames.registrationWizardName,
          builder: (context, state) => const ProfileWizardPage(),
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
          path: RouteNames.profileIntelligence,
          name: RouteNames.profileIntelligenceName,
          builder: (context, state) => const ProfileIntelligencePage(),
        ),
        GoRoute(
          path: RouteNames.choosePrompt,
          name: RouteNames.choosePromptName,
          builder: (context, state) {
            final extra = state.extra;
            final selection =
                extra is List<PromptAnswer> ? extra : const <PromptAnswer>[];
            return ChoosePromptPage(currentSelection: selection);
          },
        ),
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
          path: RouteNames.privacy,
          name: RouteNames.privacyName,
          builder: (context, state) => const PrivacyPage(),
        ),
        GoRoute(
          path: RouteNames.trustScore,
          name: RouteNames.trustScoreName,
          builder: (context, state) => const TrustScorePage(),
        ),
        GoRoute(
          path: RouteNames.partnerPreferences,
          name: RouteNames.partnerPreferencesName,
          builder: (context, state) => const PartnerPreferencesPage(),
        ),
        GoRoute(
          path: RouteNames.visitors,
          name: RouteNames.visitorsName,
          builder: (context, state) => const VisitorsPage(),
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
          path: RouteNames.profileDetail,
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
              // Defensive fallback — nothing in-app pushes this route
              // without `extra`, but a raw/deep link could theoretically
              // hit it directly.
              return MaterialPage<void>(
                key: state.pageKey,
                child: Scaffold(
                  body: Center(
                    child: Text(
                      AppLocalizations.of(context).profileDetailProfileNotAvailable,
                    ),
                  ),
                ),
              );
            }
            return MaterialPage<void>(
              key: args.pageKey,
              name: state.name ?? state.path,
              restorationId: args.pageKey.value,
              child: ProfileDetailPage(profile: args.profile, heroTag: args.heroTag),
            );
          },
        ),
        GoRoute(
          path: RouteNames.chatDetail,
          name: RouteNames.chatDetailName,
          builder: (context, state) {
            final extra = state.extra;
            if (extra is! ConversationEntity) {
              // Defensive fallback — nothing in-app pushes this route
              // without `extra`, but a raw/deep link could theoretically
              // hit it directly.
              return Scaffold(
                body: Center(
                  child: Text(
                    AppLocalizations.of(context).profileDetailProfileNotAvailable,
                  ),
                ),
              );
            }
            return ChatDetailPage(conversation: extra);
          },
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
              // TEMP DEBUG — remove before shipping.
              observers: [_DebugNavObserver('branch:discover')],
              routes: [
                GoRoute(
                  path: RouteNames.discover,
                  name: RouteNames.discoverName,
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: DiscoverPage(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              // TEMP DEBUG — remove before shipping.
              observers: [_DebugNavObserver('branch:matches')],
              routes: [
                GoRoute(
                  path: RouteNames.matches,
                  name: RouteNames.matchesName,
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: MatchesPage(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              // TEMP DEBUG — remove before shipping.
              observers: [_DebugNavObserver('branch:messages')],
              routes: [
                GoRoute(
                  path: RouteNames.messages,
                  name: RouteNames.messagesName,
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: InboxPage(),
                  ),
                ),
              ],
            ),
            StatefulShellBranch(
              // TEMP DEBUG — remove before shipping.
              observers: [_DebugNavObserver('branch:premium')],
              routes: [
                GoRoute(
                  path: RouteNames.premium,
                  name: RouteNames.premiumName,
                  pageBuilder: (context, state) => const NoTransitionPage(
                    child: PremiumPage(),
                  ),
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
    ).animate(CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    )),
    child: child,
  );
}
