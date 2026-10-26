import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../entities/profile_detail_entity.dart';

/// Contract for expanding a [DiscoveryProfileEntity] (already loaded from
/// any feed) into the richer [ProfileDetailEntity], read from
/// `GET /discover/profiles/:userId` (see ProfileDetailRemoteDataSource).
abstract class ProfileDetailRepository {
  Future<ProfileDetailEntity> getProfileDetail(DiscoveryProfileEntity base);
}
