import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../entities/profile_detail_entity.dart';

/// Contract for expanding a [DiscoveryProfileEntity] (already loaded from
/// any feed) into the richer [ProfileDetailEntity]. A future
/// `GET /api/profiles/:id`-backed implementation only needs to replace
/// [ProfileDetailRepositoryImpl] — nothing above this layer changes.
abstract class ProfileDetailRepository {
  Future<ProfileDetailEntity> getProfileDetail(DiscoveryProfileEntity base);
}
