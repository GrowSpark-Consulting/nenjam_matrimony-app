import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/backend_connectivity_checker.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../providers/splash_provider.dart';

/// Splash screen with animated logo and gradient background.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  /// Non-null once startup has failed — the splash then parks on a retryable
  /// error state instead of navigating. Cleared on retry.
  BackendConnectivityResult? _startupFailure;
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();

    _startUp();
  }

  /// Waits out the splash animation while confirming the backend is up, then
  /// routes based on session state.
  ///
  /// The health probe runs *concurrently* with the animation, so a healthy
  /// backend costs nothing: startup is still gated only on
  /// [AppConstants.splashDuration]. An unhealthy one parks here with a
  /// message and a Retry button rather than dropping the user into a shell
  /// of an app whose every request will fail.
  Future<void> _startUp() async {
    final results = await Future.wait<Object?>([
      Future<void>.delayed(AppConstants.splashDuration),
      ref.read(splashControllerProvider.notifier).checkServerHealth(),
    ]);
    if (!mounted) return;

    final health = results[1] as BackendConnectivityResult;
    if (!health.isHealthy) {
      setState(() {
        _startupFailure = health;
        _isRetrying = false;
      });
      return;
    }

    await _resolveAndNavigate();
  }

  /// Resolves the destination and navigates. Guarded: session resolution
  /// touches Firebase and the network, and an unhandled throw here would
  /// strand the user on the splash forever with no way out. Falling back to
  /// auth-selection is always a safe destination — the router's redirect
  /// re-checks the session and bounces an already-signed-in user onward.
  Future<void> _resolveAndNavigate() async {
    String route;
    try {
      route = await ref
          .read(splashControllerProvider.notifier)
          .resolveInitialRoute();
    } catch (_) {
      route = RouteNames.authSelection;
    }
    if (!mounted) return;
    context.go(route);
  }

  Future<void> _retryStartup() async {
    setState(() => _isRetrying = true);
    final health = await ref
        .read(splashControllerProvider.notifier)
        .checkServerHealth();
    if (!mounted) return;
    if (!health.isHealthy) {
      setState(() {
        _startupFailure = health;
        _isRetrying = false;
      });
      return;
    }
    setState(() {
      _startupFailure = null;
      _isRetrying = false;
    });
    await _resolveAndNavigate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppGradients.splash),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),

              // Animated Logo
              FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo Icon
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          size: 48,
                          color: AppColors.accentGold,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // App Name
                      Text(
                        AppConstants.appName,
                        style: AppTypography.headlineLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppConstants.appTagline,
                        style: AppTypography.bodyMedium.copyWith(
                          color: Colors.white60,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(flex: 3),

              FadeTransition(
                opacity: _fadeAnimation,
                child: _startupFailure == null
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accentGold,
                        ),
                      )
                    : _StartupErrorState(
                        failure: _startupFailure!,
                        isRetrying: _isRetrying,
                        onRetry: _retryStartup,
                      ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/// Terminal-but-recoverable startup state: the backend could not be reached
/// or is not serving. Rendered in place of the splash spinner so the user
/// sees why nothing is happening and can retry without force-quitting.
class _StartupErrorState extends StatelessWidget {
  const _StartupErrorState({
    required this.failure,
    required this.isRetrying,
    required this.onRetry,
  });

  final BackendConnectivityResult failure;
  final bool isRetrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (String title, String message) = switch (failure) {
      BackendUnreachable() => (
        l10n.startupUnreachableTitle,
        l10n.startupUnreachableMessage,
      ),
      BackendUnhealthy() => (
        l10n.startupUnhealthyTitle,
        l10n.startupUnhealthyMessage,
      ),
      // Unreachable in practice — a healthy result never renders this widget.
      BackendHealthy() => (l10n.commonLoading, ''),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white70, size: 36),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 44,
            child: isRetrying
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accentGold,
                    ),
                  )
                : OutlinedButton(
                    onPressed: onRetry,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                    ),
                    child: Text(l10n.commonRetry),
                  ),
          ),
        ],
      ),
    );
  }
}
