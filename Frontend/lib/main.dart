import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/config/app_config.dart';
import 'core/config/app_environment.dart';
import 'core/constants/app_constants.dart';
import 'core/network/api_providers.dart';
import 'core/network/backend_connectivity_checker.dart';
import 'core/widgets/backend_diagnostic_banner.dart';
import 'firebase_options.dart';
import 'core/providers/locale_provider.dart';
import 'core/providers/theme_mode_provider.dart';
import 'core/realtime/realtime_providers.dart';
import 'features/inbox/presentation/providers/chat_realtime_sync.dart';
import 'features/notifications/data/services/push_notification_service.dart';
import 'features/notifications/presentation/providers/notification_providers.dart';
import 'core/router/app_router.dart';
import 'core/router/route_names.dart';
import 'core/services/storage_service.dart';
import 'core/theme/app_theme.dart';
import 'features/authentication/presentation/providers/auth_providers.dart';
import 'features/registration/presentation/providers/registration_provider.dart';
import 'l10n/app_localizations.dart';
export 'core/services/storage_service.dart' show storageService;

// TEMP DEBUG — remove before shipping.
//
// Logs the moment Android's back event reaches Flutter's Router layer,
// before GoRouter/PopScope get any say — confirms whether the event is
// arriving here at all.
class _LoggingBackButtonDispatcher extends RootBackButtonDispatcher {
  @override
  Future<bool> didPopRoute() {
    debugPrint('[BACK] OS back event reached BackButtonDispatcher.didPopRoute()');
    return super.didPopRoute();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Firebase (Auth, Firestore, etc.)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Must be registered before runApp — a top-level function so the OS can
  // invoke it in a separate background isolate while the app is backgrounded
  // or terminated. See firebaseMessagingBackgroundHandler's doc comment.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Load environment variables (.env.dev) and set config. Without this,
  // AppConfig().envConfig is never assigned and any code that touches it
  // (e.g. ApiClient's base URL) throws a LateInitializationError.
  await AppConfig().init(AppEnvironment.dev);

  // Initialize local storage wrapper
  await storageService.init();

  runApp(
    const ProviderScope(
      child: NenjamMatrimonyApp(),
    ),
  );
}

/// Root application widget configuring ScreenUtil, Themes, GoRouter,
/// and reactive localization.
class NenjamMatrimonyApp extends ConsumerStatefulWidget {
  const NenjamMatrimonyApp({super.key});

  @override
  ConsumerState<NenjamMatrimonyApp> createState() =>
      _NenjamMatrimonyAppState();
}

class _NenjamMatrimonyAppState extends ConsumerState<NenjamMatrimonyApp>
    with WidgetsBindingObserver {
  // Built once and kept for the app's lifetime so locale changes don't
  // recreate the router (which would reset navigation state). Route
  // protection itself lives in createRouter's `redirect` — see
  // core/router/app_router.dart.
  late final router = createRouter(ref);

  /// Routes whose progress is worth persisting across a process kill —
  /// see StorageService.saveNavState. Anything else (splash, auth/OTP
  /// screens, ...) depends on ephemeral state that can't be resumed.
  static const _registrationRoutes = {
    RouteNames.registrationWizard,
    RouteNames.profileReview,
  };
  static const _tabRoutes = {
    RouteNames.discover,
    RouteNames.matches,
    RouteNames.messages,
    RouteNames.premium,
  };

  /// Coalesces bursts of saves (e.g. every keystroke in a wizard step) into
  /// one write ~400ms after things go quiet, so normal typing doesn't hit
  /// disk on every character. Cancelled and flushed immediately on pause —
  /// see [_saveNavStateSnapshot].
  Timer? _saveDebounce;

  /// Debug-only backend reachability check — see [_checkBackendConnectivity].
  /// Never set (and [BackendDiagnosticBanner] never built) in production.
  BackendConnectivityResult? _connectivityResult;
  bool _connectivityBannerDismissed = false;

  bool get _connectivityCheckEnabled =>
      kDebugMode && !AppConfig().environment.isProduction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Route changes (tab switches, entering/leaving the wizard) don't go
    // through build() — GoRouterDelegate notifies its own listeners
    // directly, independent of any provider. This is the fix for the
    // actual bug: the previous version only snapshotted state at
    // AppLifecycleState.paused, which is a race against the OS actually
    // killing the process — SharedPreferences.setString is an async
    // platform-channel call, and Android does not guarantee it finishes
    // before reclaiming a backgrounded process (this is especially likely
    // right after opening something memory-heavy like Gmail). Saving
    // continuously, well before the user ever backgrounds the app, removes
    // that race entirely.
    router.routerDelegate.addListener(_scheduleSave);
    if (_connectivityCheckEnabled) {
      unawaited(_checkBackendConnectivity());
    }
  }

  /// Hits the backend's /health endpoint so a dev on a physical device gets
  /// an honest "backend unreachable" banner instead of Dio's generic "No
  /// internet connection" message, which is misleading over adb reverse
  /// (see docs/development/android-usb-debugging.md). Best-effort — never
  /// blocks splash/navigation.
  Future<void> _checkBackendConnectivity() async {
    final checker = BackendConnectivityChecker(ref.read(apiClientProvider).dio);
    final result = await checker.check();
    if (mounted) {
      setState(() {
        _connectivityResult = result;
        _connectivityBannerDismissed = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    router.routerDelegate.removeListener(_scheduleSave);
    _saveDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // Flush immediately — do not wait out the debounce — this is the
        // last guaranteed moment before the OS may reclaim the process.
        _saveDebounce?.cancel();
        _saveNavStateSnapshot();
      case AppLifecycleState.resumed:
        _checkSessionOnResume();
        // Detects a permission grant made from Android Settings while the
        // app was backgrounded (the user denied the prompt initially, then
        // came back and enabled it manually) — completes FCM registration
        // immediately, no logout/login required.
        unawaited(ref.read(pushNotificationServiceProvider).checkPermissionOnResume());
      default:
        break;
    }
  }

  String get _currentLocation =>
      router.routerDelegate.currentConfiguration.uri.toString();

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _saveNavStateSnapshot);
  }

  /// Snapshots the current screen (and, if it's a registration/edit
  /// session, the draft + step + mode) so a cold start after the OS kills
  /// the process can resume exactly here. Triggered on every route change
  /// and every registration/mode change (see [initState] / [build]), not
  /// only on pause — each call fully overwrites the previous snapshot, so
  /// leaving the registration flow correctly clears it on the next save.
  void _saveNavStateSnapshot() {
    final location = _currentLocation;
    if (_registrationRoutes.contains(location)) {
      final draft = ref.read(registrationProvider);
      final mode = ref.read(profileFlowModeProvider);
      unawaited(storageService.saveNavState(
        route: location,
        registrationStep: draft.currentStep,
        profileFlowMode: mode.name,
        profileDraftJson: jsonEncode(draft.toJson()),
      ));
    } else if (_tabRoutes.contains(location)) {
      unawaited(storageService.saveNavState(route: location));
    }
    // Anything else (splash, auth/OTP, pushed detail screens like Trust
    // Score) depends on ephemeral state or isn't worth resuming into —
    // leave the last good snapshot as-is rather than overwrite it with
    // something we can't restore.
  }

  /// The process stayed alive, so GoRouter/Riverpod state is already
  /// intact for free — never re-shows splash or restarts anything. The
  /// only thing that can have changed while backgrounded is the auth
  /// session itself (token revoked/expired), so bounce to login if that
  /// happened.
  void _checkSessionOnResume() {
    final signedIn = ref.read(authRepositoryProvider).currentUser != null;
    final location = _currentLocation;
    final willRedirect = !signedIn && !RouteNames.publicRoutes.contains(location);
    if (willRedirect) {
      router.go(RouteNames.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Single source of truth for "did the signed-in user just sign out?" —
    // covers every logout path (Settings, drawer, token expiry, etc.), not
    // just the explicit logout buttons, so ProfileFlowMode/ProfileDraft can
    // never leak from one signed-in user into the next session on this
    // device.
    ref.listen(authStateChangesProvider, (previous, next) {
      final wasSignedIn = previous?.value != null;
      final isNowSignedOut = !next.isLoading && next.value == null;
      if (wasSignedIn && isNowSignedOut) {
        // Full local session teardown — the one place this runs, regardless
        // of which entry point (Settings, nav drawer, background 401
        // recovery) triggered the Firebase sign-out that landed here.
        ref.read(registrationProvider.notifier).startCreateMode();
        unawaited(storageService.clearNavState());
        unawaited(storageService.clearUserData());
        unawaited(storageService.clearPendingPhone());
      }
    });

    // registrationProvider changes (wizard step advancing, a field being
    // edited) and profileFlowModeProvider changes (create ↔ edit) don't
    // change the URL, so the route-change listener in initState() never
    // fires for them — without this, "step 5 → home → Gmail → return"
    // would restore into the wizard at whatever step it opened on, not
    // step 5. Re-snapshot on every such change too.
    ref.listen(registrationProvider, (previous, next) => _scheduleSave());
    ref.listen(profileFlowModeProvider, (previous, next) => _scheduleSave());

    // Rebuilds the app instantly whenever the user changes language.
    final locale = ref.watch(localeProvider);

    // Keeps the real-time socket connected to the signed-in user and turns
    // inbound interest/notification/shortlist events into targeted provider
    // refreshes (no manual pull-to-refresh needed). Alive for the whole session.
    ref.watch(realtimeSyncProvider);

    // Applies inbound chat socket events (messages, edits/deletes, read/
    // delivered receipts, typing) to the inbox state. Also alive for the session.
    ref.watch(chatRealtimeSyncProvider);

    // Starts/stops FCM (permission, token registration/refresh, foreground
    // and tap handling) with the signed-in session. Also alive for the session.
    ref.watch(pushNotificationSyncProvider);

    // Initialize responsive screen scaling (design size based on standard phone: 375x812)
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          restorationScopeId: 'nenjam_app',
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,

          // Theme Configuration
          themeMode: ref.watch(themeModeProvider),
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,

          // Localization
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,

          // Routing
          // TEMP DEBUG — normally just `routerConfig: router`; expanded to
          // individual params so a logging BackButtonDispatcher can be
          // swapped in. Revert to `routerConfig: router` when done.
          routeInformationProvider: router.routeInformationProvider,
          routeInformationParser: router.routeInformationParser,
          routerDelegate: router.routerDelegate,
          backButtonDispatcher: _LoggingBackButtonDispatcher(),

          builder: _connectivityCheckEnabled
              ? (context, child) => _wrapWithConnectivityBanner(child)
              : null,
        );
      },
    );
  }

  Widget _wrapWithConnectivityBanner(Widget? child) {
    final result = _connectivityResult;
    final content = child ?? const SizedBox.shrink();
    if (result == null || result is BackendHealthy || _connectivityBannerDismissed) {
      return content;
    }
    return Stack(
      children: [
        content,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: BackendDiagnosticBanner(
              result: result,
              onRetry: _checkBackendConnectivity,
              onDismiss: () => setState(() => _connectivityBannerDismissed = true),
            ),
          ),
        ),
      ],
    );
  }
}
