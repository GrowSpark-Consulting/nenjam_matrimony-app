import 'dart:async';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:geolocator/geolocator.dart';

/// Outcome of asking the device where it is.
///
/// A sealed result rather than a nullable `Position` plus a thrown exception,
/// because "we did not get a location" is not one state — it is five, and each
/// one needs a different thing offered to the user:
///
///   * [LocationSuccess]                    — got a fix, show profiles.
///   * [LocationPermissionDenied]           — offer "Enable Location" (retry).
///   * [LocationPermissionPermanentlyDenied] — retrying shows no dialog; the
///     only way back is the app's settings screen.
///   * [LocationServiceDisabled]            — permission is irrelevant, GPS is
///     off device-wide; the fix is the OS location settings screen.
///   * [LocationUnavailable]                — timed out, unsupported platform,
///     or the plugin failed; offer a plain retry.
///
/// Collapsing these into one "error" is what produces the classic dead end
/// where a user taps "Enable Location" forever against a dialog the OS has
/// stopped showing.
sealed class LocationResult {
  const LocationResult();
}

/// A usable fix.
class LocationSuccess extends LocationResult {
  const LocationSuccess({
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
  });

  final double latitude;
  final double longitude;

  /// Radius of uncertainty the device reported, in metres.
  final double accuracyMetres;

  /// Whether this looks like an Android 12+ "Approximate" / iOS reduced-accuracy
  /// grant rather than a precise fix.
  ///
  /// Inferred from the reported accuracy because neither platform exposes the
  /// user's Precise/Approximate choice as a flag readable after the fact —
  /// a coarse grant simply returns a deliberately fuzzed position with a large
  /// accuracy radius (typically 1-3km, versus tens of metres for a precise
  /// one). The threshold sits well above any precise fix and well below the
  /// coarse floor, so it does not straddle a real boundary.
  ///
  /// Nothing is blocked either way — approximate is a fully supported mode, and
  /// this only decides whether the UI describes the result as approximate.
  bool get isApproximate => accuracyMetres >= 500;
}

/// The user declined, but the OS will ask again — a retry is worth offering.
class LocationPermissionDenied extends LocationResult {
  const LocationPermissionDenied();
}

/// Denied in a way the OS will not re-prompt for ("Don't allow" twice on
/// Android, or any denial on iOS after the first). Only the app settings
/// screen can undo it.
class LocationPermissionPermanentlyDenied extends LocationResult {
  const LocationPermissionPermanentlyDenied();
}

/// Location services are switched off for the whole device. Distinct from a
/// permission denial: the app could hold every permission and still get
/// nothing, and the user has to fix it in the OS settings, not the app's.
class LocationServiceDisabled extends LocationResult {
  const LocationServiceDisabled();
}

/// Timed out, ran on a platform without location support, or the plugin threw.
class LocationUnavailable extends LocationResult {
  const LocationUnavailable([this.message]);

  final String? message;
}

/// Device location, as the rest of the app sees it.
///
/// An interface so the Near Me providers can be driven by a fake in tests —
/// there is no way to grant or deny an OS permission from a widget test, so an
/// injectable seam is the only way this flow is testable at all.
/// [DeviceLocationServiceImpl] is the single place that imports geolocator.
abstract class DeviceLocationService {
  /// Current permission state WITHOUT prompting. Used on entry so an
  /// already-granted user never sees a dialog.
  Future<LocationResult?> checkPermissionOnly();

  /// Prompts if needed, then reads a position.
  ///
  /// Safe to call when permission is already granted (no dialog appears) and
  /// when it is permanently denied (the OS shows nothing and the result says
  /// so, rather than hanging).
  Future<LocationResult> requestAndFetch();

  /// Opens the OS location-services screen — the fix for
  /// [LocationServiceDisabled]. Returns whether the screen could be opened.
  Future<bool> openLocationSettings();
}

class DeviceLocationServiceImpl implements DeviceLocationService {
  const DeviceLocationServiceImpl();

  /// Ceiling on how long to wait for a fix.
  ///
  /// A cold GPS start indoors can hang for minutes; geolocator itself imposes
  /// no limit, so without this the Near Me screen would sit on its loading
  /// state with no way out. Fifteen seconds is long enough for a realistic
  /// cold start and short enough that a stuck request still returns something
  /// actionable.
  static const _fixTimeout = Duration(seconds: 15);

  @override
  Future<LocationResult?> checkPermissionOnly() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationServiceDisabled();
      }
      final permission = await Geolocator.checkPermission();
      return switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse => null, // Granted — nothing to report.
        LocationPermission.denied => const LocationPermissionDenied(),
        LocationPermission.deniedForever =>
          const LocationPermissionPermanentlyDenied(),
        LocationPermission.unableToDetermine => const LocationUnavailable(),
      };
    } on MissingPluginException catch (_) {
      // Platform without the geolocator plugin registered.
      return const LocationUnavailable('Location is not supported here.');
    } catch (error) {
      return LocationUnavailable(error.toString());
    }
  }

  @override
  Future<LocationResult> requestAndFetch() async {
    try {
      // Services first: on a device with location switched off, requesting
      // permission can succeed and the position read then fails anyway — which
      // would show the user the wrong remedy.
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationServiceDisabled();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // This is the call that raises the native dialog — the one offering
        // Precise/Approximate and While using the app/Only this time. Every
        // one of those outcomes lands in the switch below; "Only this time"
        // grants whileInUse for this session and is treated as granted, which
        // is exactly right: it works now, and the next launch asks again.
        permission = await Geolocator.requestPermission();
      }

      switch (permission) {
        case LocationPermission.denied:
          return const LocationPermissionDenied();
        case LocationPermission.deniedForever:
          return const LocationPermissionPermanentlyDenied();
        case LocationPermission.unableToDetermine:
          return const LocationUnavailable();
        case LocationPermission.always:
        case LocationPermission.whileInUse:
          break;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // `medium` rather than `best`: a matrimony radius search is accurate
          // to the kilometre, and asking for the highest accuracy keeps the GPS
          // radio on longer and drains battery for precision that is discarded
          // by the time it is rounded for display. It also degrades gracefully
          // when the user granted only Approximate, where `best` cannot be
          // honoured anyway.
          accuracy: LocationAccuracy.medium,
          timeLimit: _fixTimeout,
        ),
      );

      return LocationSuccess(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMetres: position.accuracy,
      );
    } on TimeoutException catch (_) {
      return const LocationUnavailable('Timed out waiting for a location.');
    } on LocationServiceDisabledException catch (_) {
      // Services can be switched off between the check above and the fix.
      return const LocationServiceDisabled();
    } on PermissionDeniedException catch (_) {
      return const LocationPermissionDenied();
    } on MissingPluginException catch (_) {
      return const LocationUnavailable('Location is not supported here.');
    } catch (error) {
      return LocationUnavailable(error.toString());
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }
}
