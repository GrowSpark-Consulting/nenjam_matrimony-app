import '../../../discover/data/models/discovery_profile_model.dart';
import '../../domain/entities/blocked_user_entity.dart';

/// Wire model for [BlockedUserEntity] — `profile` is parsed with the exact
/// same [DiscoveryProfileModel.fromJson] every other feed/list uses, since
/// the backend returns the identical Discover card shape for it.
class BlockedUserModel extends BlockedUserEntity {
  BlockedUserModel({required super.profile, required super.blockedAt});

  factory BlockedUserModel.fromJson(Map<String, dynamic> json) {
    return BlockedUserModel(
      profile: DiscoveryProfileModel.fromJson(
        json['profile'] as Map<String, dynamic>,
      ),
      blockedAt:
          DateTime.tryParse(json['blockedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
