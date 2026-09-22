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
import 'firebase_options.dart';
import 'core/providers/locale_provider.dart';
import 'core/realtime/realtime_providers.dart';
import 'features/inbox/presentation/providers/chat_realtime_sync.dart';
import 'features/inbox/presentation/providers/inbox_providers.dart';
import 'features/notifications/data/services/push_notification_service.dart';
import 'features/notifications/presentation/providers/notification_providers.dart';
import 'core/router/app_router.dart';
import 'core/router/route_names.dart';
import 'core/utils/photo_trace.dart';
import 'core/services/storage_service.dart';
import 'core/utils/story_perf.dart';
import 'core/theme/app_theme.dart';
import 'features/authentication/domain/services/local_auth_session.dart';
import 'features/authentication/presentation/providers/auth_providers.dart';
import 'features/profile/presentation/providers/profile_dashboard_providers.dart';
import 'features/profile/presentation/providers/profile_providers.dart';
import 'features/profile_photos/presentation/providers/photo_providers.dart';
import 'features/verification/presentation/providers/face_verification_providers.dart';
import 'features/registration/presentation/providers/registration_provider.dart';
import 'l10n/app_localizations.dart';
export 'core/services/storage_service.dart' show storageService;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StoryPerf.start('main() entered');

  // These four are mutually independent — each needs only the binding above,
  // none reads anything another produces — so they run concurrently instead
  // of one after another. Startup waits for the slowest rather than the sum.
  //
  //  · orientation lock — a platform-channel call nothing else consults. Kept
  //    inside the barrier rather than deferred past runApp so the very first
  //    frame can never paint in landscape and then snap upright.
  //  · Firebase — must finish before onBackgroundMessage (below) and before
  //    any auth provider is read, which is why that call stays after the wait.
  //  · AppConfig — loads a bundled .env asset via rootBundle. Swallows its own
  //    errors internally, so it can never be the one that fails this group.
  //  · storage — SharedPreferences, read synchronously by SplashController
  //    (hasSelectedLanguage), so it must still be ready before runApp.
  //
  // Failure behaviour is unchanged: previously any of these throwing aborted
  // main() and took the launch down; Future.wait propagates the first error
  // the same way. Nothing here is newly allowed to fail silently.
  await Future.wait<Object?>([
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    // A release build is production by definition — the flavor is never
    // hardcoded to dev. Note the API origin does NOT come from here; it is
    // AppConstants.apiBaseUrl (override with --dart-define=API_BASE_URL=...).
    AppConfig().init(
      kReleaseMode ? AppEnvironment.production : AppEnvironment.dev,
    ),
    storageService.init(),
  ]);
  StoryPerf.mark('init complete (orientation+firebase+config+storage)');

  // Must be registered before runApp — a top-level function so the OS can
  // invoke it in a separate background isolate while the app is backgrounded
  // or terminated. See firebaseMessagingBackgroundHandler's doc comment.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const ProviderScope(child: NenjamMatrimonyApp()));
  StoryPerf.mark('runApp() called');
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => StoryPerf.mark('first frame rendered'),
  );
}

/// Root application widget configuring ScreenUtil, Themes, GoRouter,
/// and reactive localization.
class NenjamMatrimonyApp extends ConsumerStatefulWidget {
  const NenjamMatrimonyApp({super.key});

  @override
  ConsumerState<NenjamMatrimonyApp> createState() => _NenjamMatrimonyAppState();
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
    RouteNames.profileEdit,
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
      case AppLifecycleState.detached:
        // Flush immediately — do not wait out the debounce — this is the
        // last guaranteed moment before the OS may reclaim the process.
        _saveDebounce?.cancel();
        _saveNavStateSnapshot();
        // Tell peers we're offline now (with a last-seen) and pause the
        // presence heartbeat — see RealtimeService.handleAppBackgrounded.
        ref.read(realtimeServiceProvider).handleAppBackgrounded();
      case AppLifecycleState.resumed:
        _checkSessionOnResume();
        // Reconnect if needed and re-announce online instantly.
        ref.read(realtimeServiceProvider).handleAppForegrounded();
        _resyncUnreadOnResume();
        // Detects a permission grant made from Android Settings while the
        // app was backgrounded (the user denied the prompt initially, then
        // came back and enabled it manually) — completes FCM registration
        // immediately, no logout/login required.
        unawaited(
          ref.read(pushNotificationServiceProvider).checkPermissionOnResume(),
        );
      default:
        // inactive / hidden are transient (app switcher, incoming call) —
        // acting here would flap presence; let paused/resumed drive it.
        break;
    }
  }

  /// Re-syncs the conversations list on every foreground so the bottom nav's
  /// unread badge reflects whatever happened while the app was away —
  /// messages that arrived as pushes with no live socket to deliver them, or
  /// a thread read on another device.
  ///
  /// [ChatRealtimeSync]'s `onReady` listener already covers the case where
  /// the socket actually dropped, but a short background (glance at a
  /// notification, answer a call) often comes back with the connection
  /// intact, so `onReady` never fires and nothing else would refetch.
  ///
  /// Gated on being signed in: `.notifier` *creates* the provider if it
  /// doesn't exist yet, and resuming on the splash or an auth screen must not
  /// be what kicks off a `GET /conversations`.
  void _resyncUnreadOnResume() {
    if (ref.read(currentAuthUserProvider) == null) return;
    unawaited(
      ref.read(conversationsNotifierProvider.notifier).refreshSilently(),
    );
  }

  String get _currentLocation =>
      router.routerDelegate.currentConfiguration.uri.toString();

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(
      const Duration(milliseconds: 400),
      _saveNavStateSnapshot,
    );
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
      unawaited(
        storageService.saveNavState(
          route: location,
          registrationStep: draft.currentStep,
          profileFlowMode: mode.name,
          profileDraftJson: jsonEncode(draft.toJson()),
        ),
      );
    } else if (_tabRoutes.contains(location)) {
      unawaited(storageService.saveNavState(route: location));
    }
    // Anything else (splash, auth/OTP, pushed detail screens) depends on
    // ephemeral state or isn't worth resuming into —
    // leave the last good snapshot as-is rather than overwrite it with
    // something we can't restore.
  }

  /// The process stayed alive, so GoRouter/Riverpod state is already
  /// intact for free — never re-shows splash or restarts anything. The
  /// only thing that can have changed while backgrounded is the auth
  /// session itself (token revoked/expired), so bounce to the sign-up
  /// landing screen if that happened — the same destination the router's
  /// own redirect uses, so the two can't disagree.
  void _checkSessionOnResume() {
    // `hasLocalAuthSession` is the same allowance the router's guard makes
    // for a mobile login that could not mint a Firebase session — without
    // it, resuming the app would bounce that member to the landing screen
    // from a screen the router itself considers theirs.
    final signedIn = ref.read(authRepositoryProvider).currentUser != null ||
        hasLocalAuthSession();
    final location = _currentLocation;
    final willRedirect =
        !signedIn && !RouteNames.publicRoutes.contains(location);
    if (willRedirect) {
      router.go(RouteNames.registrationLanding);
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
        // TEMPORARY (PhotoTrace) — a sign-out landing in the middle of a
        // photo trace is exactly the failure being investigated: it is what
        // clears the providers below out from under an in-flight upload.
        PhotoTrace.step('!! SESSION TEARDOWN (signed out) !!');
        // Full local session teardown — the one place this runs, regardless
        // of which entry point (Settings, nav drawer, background 401
        // recovery) triggered the Firebase sign-out that landed here.
        ref.read(registrationProvider.notifier).startCreateMode();
        unawaited(storageService.clearNavState());
        unawaited(storageService.clearUserData());
        unawaited(storageService.clearPendingPhone());
        // The signed-in user's server-backed state lives in root-scoped,
        // non-autoDispose providers, so it survives for the whole process
        // unless it is dropped here: the next member to sign in on this
        // device would otherwise open the photo step on the PREVIOUS
        // member's photos (and their avatar in the drawer/Discover bar).
        //
        // It also unsticks a latched failure. These are AsyncNotifier/
        // FutureProviders that are built once; a fetch that failed while the
        // session was going away leaves an AsyncError no later sign-in ever
        // rebuilds, which is what made PhotoManagerSection show its retry
        // state instead of the add-photo tile for the rest of the run.
        ref.invalidate(myPhotosProvider);
        ref.invalidate(myProfileProvider);
        ref.invalidate(profileDraftResponseProvider);
        ref.invalidate(faceVerificationStatusProvider);
      }

      // The other half: rebuild that same server-backed state whenever a
      // session BEGINS (a fresh login, an account switch, or the persisted
      // session finishing its restore after launch).
      //
      // These providers are built the first time something watches them,
      // which can be before Firebase has restored `currentUser`. That fetch
      // goes out unauthenticated and fails, and because nothing rebuilt them
      // afterwards the AsyncError stuck for the rest of the process — the
      // photo step then showed its retry state, and the member's photos were
      // "missing" until the app was restarted into a luckier ordering.
      // Keying on the uid rather than a bare non-null covers an account
      // switch too, where the stale data belongs to a different person.
      final previousUid = previous?.valueOrNull?.uid;
      final nextUid = next.valueOrNull?.uid;
      if (nextUid != null && nextUid != previousUid) {
        PhotoTrace.step('session ready — rebuilding profile/photo providers');
        ref.invalidate(myPhotosProvider);
        ref.invalidate(myProfileProvider);
        ref.invalidate(profileDraftResponseProvider);
        ref.invalidate(faceVerificationStatusProvider);
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

          // Theme Configuration — Nenjam is light-mode only. The app must
          // render the light theme regardless of the device's system
          // appearance, so the mode is a hard constant (never a provider or
          // stored preference) and no dark ThemeData is supplied at all.
          themeMode: ThemeMode.light,
          theme: AppTheme.light,

          // Localization
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,

          // Routing
          routerConfig: router,
        );
      },
    );
  }
}
