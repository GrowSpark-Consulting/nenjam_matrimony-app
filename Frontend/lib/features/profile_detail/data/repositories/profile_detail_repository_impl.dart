import '../../../discover/domain/entities/discovery_profile_entity.dart';
import '../../domain/entities/profile_detail_entity.dart';
import '../../domain/repositories/profile_detail_repository.dart';
import '../datasources/profile_detail_mock_datasource.dart';

class ProfileDetailRepositoryImpl implements ProfileDetailRepository {
  ProfileDetailRepositoryImpl(this._dataSource);

  final ProfileDetailMockDataSource _dataSource;

  @override
  Future<ProfileDetailEntity> getProfileDetail(DiscoveryProfileEntity base) =>
      _dataSource.fetchProfileDetail(base);
}
