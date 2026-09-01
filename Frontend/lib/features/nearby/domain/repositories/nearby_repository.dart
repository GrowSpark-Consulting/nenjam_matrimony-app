import '../../../discover/domain/entities/discovery_profile_entity.dart';

/// Backend access for the Near Me feature.
///
/// An interface (with [NearbyRepositoryImpl] behind it) to match every other
/// feature in this app, and so the providers can be driven by a fake in tests
/// without a live API.
abstract class NearbyRepository {
  /// Profiles within [radiusKm] of the given point, nearest first.
  ///
  /// Every returned profile carries a non-null `distanceKm`. Other members'
  /// coordinates are never part of the response — the server sends only the
  /// calculated distance.
  Future<List<DiscoveryProfileEntity>> getNearbyProfiles({
    required double latitude,
    required double longitude,
    double radiusKm,
    int page,
    int limit,
  });

  /// Stores the caller's own coordinates so other members can find them.
  ///
  /// Separate from [getNearbyProfiles] because it is a write with its own
  /// failure mode, and because being *findable* is a different thing from
  /// *finding* — one can succeed while the other fails.
  Future<void> updateMyLocation({
    required double latitude,
    required double longitude,
    int? accuracyMetres,
  });
}
