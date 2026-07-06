import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/services/storage_service.dart';

/// Resolves where the app should navigate once the splash animation
/// completes, based on persisted local state.
///
/// Keeping this decision out of the widget lets the splash page stay a
/// pure presentation layer. Reads are synchronous because
/// [StorageService] is already initialized during app bootstrap.
class SplashController extends Notifier<void> {
  @override
  void build() {}

  /// The first route the user should land on after the splash:
  /// - Authentication, if a language has already been chosen.
  /// - Language selection, on first launch.
  String resolveInitialRoute() {
    return storageService.isLoggedIn
        ? RouteNames.home
        : RouteNames.language;
  }
}

/// Global provider exposing the splash navigation decision.
final splashControllerProvider =
    NotifierProvider<SplashController, void>(SplashController.new);
