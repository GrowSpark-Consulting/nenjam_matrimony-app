import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/presentation/pages/login_page.dart';
import '../../features/authentication/presentation/pages/otp_page.dart';
import '../../features/chat/presentation/pages/chat_page.dart';
import '../../features/help/presentation/pages/help_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/language/presentation/pages/language_page.dart';
import '../../features/matches/presentation/pages/matches_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_page.dart';
import '../../features/premium/presentation/pages/premium_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/registration/presentation/pages/create_profile_for_page.dart';
import '../../features/registration/presentation/pages/profile_review_page.dart';
import '../../features/registration/presentation/pages/profile_wizard_page.dart';
import '../../features/registration/presentation/pages/registration_page.dart';
import '../../features/search/presentation/pages/search_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/splash/presentation/pages/splash_page.dart';
import '../../features/subscription/presentation/pages/subscription_page.dart';
import '../../features/verification/presentation/pages/verification_page.dart';
import '../widgets/navigation/app_bottom_nav.dart';
import 'route_names.dart';

/// Nenjam Matrimony — GoRouter Configuration
///
/// Defines all app routes with:
/// - Shell route for bottom navigation
/// - Smooth page transitions
/// - Named routes for type-safe navigation
final GlobalKey<NavigatorState> _rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'shell');

GoRouter createRouter() => GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: RouteNames.splash,
      debugLogDiagnostics: true,
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
          path: RouteNames.onboarding,
          name: RouteNames.onboardingName,
          builder: (context, state) => const OnboardingPage(),
        ),
        GoRoute(
          path: RouteNames.login,
          name: RouteNames.loginName,
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: RouteNames.otp,
          name: RouteNames.otpName,
          builder: (context, state) => const OtpPage(),
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
          path: RouteNames.registrationWizard,
          name: RouteNames.registrationWizardName,
          builder: (context, state) => const ProfileWizardPage(),
        ),
        GoRoute(
          path: RouteNames.profileReview,
          name: RouteNames.profileReviewName,
          builder: (context, state) => const ProfileReviewPage(),
        ),
        GoRoute(
          path: RouteNames.premium,
          name: RouteNames.premiumName,
          pageBuilder: (context, state) => CustomTransitionPage(
            key: state.pageKey,
            child: const PremiumPage(),
            transitionsBuilder: _slideUpTransition,
          ),
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

        // ─── Shell Route with Bottom Navigation ───────────────────
        ShellRoute(
          navigatorKey: _shellNavigatorKey,
          builder: (context, state, child) => AppBottomNavShell(child: child),
          routes: [
            GoRoute(
              path: RouteNames.home,
              name: RouteNames.homeName,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: HomePage(),
              ),
            ),
            GoRoute(
              path: RouteNames.search,
              name: RouteNames.searchName,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: SearchPage(),
              ),
            ),
            GoRoute(
              path: RouteNames.matches,
              name: RouteNames.matchesName,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: MatchesPage(),
              ),
            ),
            GoRoute(
              path: RouteNames.chat,
              name: RouteNames.chatName,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ChatPage(),
              ),
            ),
            GoRoute(
              path: RouteNames.notifications,
              name: RouteNames.notificationsName,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: NotificationsPage(),
              ),
            ),
            GoRoute(
              path: RouteNames.profile,
              name: RouteNames.profileName,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ProfilePage(),
              ),
            ),
          ],
        ),
      ],
    );

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
