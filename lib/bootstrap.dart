import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/config/app_config.dart';
import 'core/config/app_environment.dart';
import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/services/storage_service.dart';
import 'core/theme/app_theme.dart';

/// Global storage service instance.
final storageService = StorageService();

/// Global app config instance.
final appConfig = AppConfig();

/// Shared bootstrap initialization logic for all environment flavors.
Future<void> bootstrap(AppEnvironment environment) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Load environment variables (.env) and set config
  await appConfig.init(environment);

  // Initialize storage
  await storageService.init();

  runApp(
    const ProviderScope(
      child: NenjamMatrimonyApp(),
    ),
  );
}

/// Root application widget configuring ScreenUtil, Themes, and GoRouter.
class NenjamMatrimonyApp extends StatefulWidget {
  const NenjamMatrimonyApp({super.key});

  @override
  State<NenjamMatrimonyApp> createState() => _NenjamMatrimonyAppState();
}

class _NenjamMatrimonyAppState extends State<NenjamMatrimonyApp> {
  late final router = createRouter();

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: '${AppConstants.appName}${appConfig.environment.isProduction ? "" : " (${appConfig.environment.name.toUpperCase()})"}',
          debugShowCheckedModeBanner: !appConfig.environment.isProduction,

          // Theme Configuration
          themeMode: storageService.themeMode,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,

          // Routing
          routerConfig: router,
        );
      },
    );
  }
}
