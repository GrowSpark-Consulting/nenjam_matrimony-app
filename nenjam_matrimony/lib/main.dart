import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/services/storage_service.dart';
import 'core/theme/app_theme.dart';
export 'core/services/storage_service.dart' show storageService;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize local storage wrapper
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

          // Routing
          routerConfig: router,
        );
      },
    );
  }
}
