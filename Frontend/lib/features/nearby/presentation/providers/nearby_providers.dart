import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../../../core/services/location/device_location_service.dart';
import '../../../../core/services/location/location_providers.dart';
import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../data/repositories/nearby_repository_impl.dart';
import '../../domain/repositories/nearby_repository.dart';

/// Real backend-backed repository — `GET /profiles/nearby` and
/// `PUT /profiles/me/location` through the shared authenticated [ApiClient].
final nearbyRepositoryProvider = Provider<NearbyRepository>(
  (ref) => NearbyRepositoryImpl(ref.watch(apiClientProvider)),
);

/// Everything the Near Me screen can be showing.
///
/// A sealed state rather than `AsyncValue<List<Profile>>` because three of
/// these are not errors and must not be rendered as one: a denied permission,
/// switched-off location services and an empty result are ordinary outcomes
/// with their own copy and their own button. Squeezing them through
/// `AsyncValue.error` is what produces a red failure screen for a user who
/// simply has not tapped Allow yet.
sealed class NearbyState {
  const NearbyState();
}

/// Nothing has been asked for yet — no permission checked, no GPS read, no
/// request sent.
///
/// This is the initial state, and it is what keeps Near Me lazy. The Discover
/// feed shows this surface to every user who opens the tab, so resolving on
/// creation would mean a location check (and, for a first-time user, a system
/// dialog) fired by nothing more than scrolling past a section. Work starts
/// only when something calls [NearbyNotifier.resolveIfIdle] (the dedicated
/// screen, on open) or [NearbyNotifier.requestPermissionAndLoad] (the
/// "Enable Location" button).
class NearbyIdle extends NearbyState {
  const NearbyIdle();
}

/// Acquiring a fix, or fetching profiles for one. Deliberately one state
/// rather than two: both take a moment, both show "Finding people near you…",
/// and splitting them would make the label flicker mid-load.
class NearbyLoading extends NearbyState {
  const NearbyLoading();
}

/// Profiles for a known location. [profiles] may be empty — that is the empty
/// state, not a failure.
class NearbyLoaded extends NearbyState {
  const NearbyLoaded({
    required this.profiles,
    required this.radiusKm,
    required this.isApproximate,
  });

  final List<DiscoveryProfileEntity> profiles;

  /// Radius actually searched, so the empty-state copy names the real number.
  final double radiusKm;

  /// Whether the fix came from a coarse ("Approximate") grant. Purely a
  /// labelling concern — results are shown either way.
  final bool isApproximate;
}

/// No location permission. [isPermanentlyDenied] decides which remedy the UI
/// offers: retrying the prompt is pointless once the OS has stopped showing
/// it, and the only route back is the app's settings screen.
class NearbyPermissionRequired extends NearbyState {
  const NearbyPermissionRequired({required this.isPermanentlyDenied});

  final bool isPermanentlyDenied;
}

/// Location services are off for the whole device — a different problem from a
/// denied permission, fixed on a different settings screen.
class NearbyLocationServicesOff extends NearbyState {
  const NearbyLocationServicesOff();
}

/// Could not obtain a position (timeout, unsupported device, plugin failure).
class NearbyLocationFailure extends NearbyState {
  const NearbyLocationFailure();
}

/// Got a position, but the profile request failed. Kept distinct from
/// [NearbyLocationFailure] so the screen does not tell someone their location
/// is broken when the real problem is the network or the API.
class NearbyFetchFailure extends NearbyState {
  const NearbyFetchFailure();
}

/// Drives the Near Me screen end to end: permission, position, then profiles.
///
/// A [Notifier] rather than an [AsyncNotifier] because the flow's outcomes are
/// the sealed states above, not loading/data/error.
class NearbyNotifier extends Notifier<NearbyState> {
  bool _disposed = false;

  /// Guards against a second in-flight run — the OS shows only one permission
  /// dialog, and a double tap on "Enable Location" would otherwise queue a
  /// second request behind it and re-render the screen twice.
  bool _isRunning = false;

  @override
  NearbyState build() {
    ref.onDispose(() => _disposed = true);

    // Deliberately does NO work. Watching this provider must stay free of side
    // effects, because the Discover feed watches it to decide what to render
    // and merely opening Discover must not read the device location. See
    // [NearbyIdle].
    return const NearbyIdle();
  }

  /// Resolve once, without ever prompting — for a surface whose whole purpose
  /// is Near Me, so opening it should go straight to results when permission
  /// is already granted.
  ///
  /// No-ops unless the state is still [NearbyIdle]. That is what makes
  /// re-entering the screen, or rebuilding it, free: results already loaded
  /// (or a permission state already determined) are reused rather than
  /// refetched, so no second GPS read or API call is issued.
  Future<void> resolveIfIdle() async {
    if (state is! NearbyIdle) return;
    await _run(promptIfNeeded: false);
  }

  /// Entry point for the "Enable Location" button — the one path allowed to
  /// raise the OS dialog, because it follows a deliberate user tap.
  Future<void> requestPermissionAndLoad() => _run(promptIfNeeded: true);

  /// Retry that re-checks permission but does not prompt. Used by pull-to-
  /// refresh and the generic "Try Again" button.
  Future<void> refresh() => _run(promptIfNeeded: false);

  /// Opens the OS location-services screen for [NearbyLocationServicesOff],
  /// then re-checks — the user may come back with services switched on.
  Future<void> openLocationSettings() async {
    await ref.read(deviceLocationServiceProvider).openLocationSettings();
  }

  Future<void> _run({required bool promptIfNeeded}) async {
    if (_isRunning) return;
    _isRunning = true;
    _set(const NearbyLoading());

    try {
      final location = ref.read(deviceLocationServiceProvider);

      // Without a deliberate tap, only ever LOOK at the permission — never
      // prompt. Opening a screen that immediately throws a system dialog is
      // the pattern that trains people to hit "Don't allow" on reflex.
      if (!promptIfNeeded) {
        final blocker = await location.checkPermissionOnly();
        if (blocker != null) {
          _set(_stateForFailure(blocker));
          return;
        }
      }

      final result = await location.requestAndFetch();
      if (result is! LocationSuccess) {
        _set(_stateForFailure(result));
        return;
      }

      await _loadProfiles(result);
    } finally {
      _isRunning = false;
    }
  }

  Future<void> _loadProfiles(LocationSuccess fix) async {
    final repository = ref.read(nearbyRepositoryProvider);

    // Store the caller's own position so OTHER members can find them. Failing
    // to do so is deliberately not fatal: being findable and finding are
    // separate concerns, and a user who granted location should still see
    // their results if this write happens to fail.
    try {
      await repository.updateMyLocation(
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracyMetres: fix.accuracyMetres.isFinite
            ? fix.accuracyMetres.round()
            : null,
      );
    } catch (_) {
      // Intentionally swallowed — see above.
    }

    try {
      final profiles = await repository.getNearbyProfiles(
        latitude: fix.latitude,
        longitude: fix.longitude,
        radiusKm: NearbyRepositoryImpl.defaultRadiusKm,
      );
      _set(
        NearbyLoaded(
          profiles: profiles,
          radiusKm: NearbyRepositoryImpl.defaultRadiusKm,
          isApproximate: fix.isApproximate,
        ),
      );
    } catch (_) {
      _set(const NearbyFetchFailure());
    }
  }

  NearbyState _stateForFailure(LocationResult result) => switch (result) {
    LocationPermissionDenied() => const NearbyPermissionRequired(
      isPermanentlyDenied: false,
    ),
    LocationPermissionPermanentlyDenied() => const NearbyPermissionRequired(
      isPermanentlyDenied: true,
    ),
    LocationServiceDisabled() => const NearbyLocationServicesOff(),
    LocationUnavailable() => const NearbyLocationFailure(),
    // A success never reaches here; mapping it keeps the switch exhaustive so
    // adding a LocationResult variant becomes a compile error, not a silent
    // fall-through to a wrong screen.
    LocationSuccess() => const NearbyLocationFailure(),
  };

  /// Assigning to a disposed notifier throws. The user can leave the screen
  /// while a fix or a request is still in flight, so every write goes through
  /// here.
  void _set(NearbyState next) {
    if (_disposed) return;
    state = next;
  }
}

final nearbyNotifierProvider = NotifierProvider<NearbyNotifier, NearbyState>(
  NearbyNotifier.new,
);
