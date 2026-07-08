import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/constants/app_constants.dart';
import 'firebase_options.dart';
import 'core/providers/locale_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/storage_service.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
export 'core/services/storage_service.dart' show storageService;

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

class _NenjamMatrimonyAppState extends ConsumerState<NenjamMatrimonyApp> {
  // Built once and kept for the app's lifetime so locale changes don't
  // recreate the router (which would reset navigation state).
  late final router = createRouter();

  @override
  Widget build(BuildContext context) {
    // Rebuilds the app instantly whenever the user changes language.
    final locale = ref.watch(localeProvider);

    // Initialize responsive screen scaling (design size based on standard phone: 375x812)
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,

          // Theme Configuration
          themeMode: storageService.themeMode,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,

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
