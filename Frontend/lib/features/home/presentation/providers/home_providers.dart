import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/home_mock_datasource.dart';
import '../../data/repositories/home_repository_impl.dart';
import '../../domain/entities/home_feed_entity.dart';
import '../../domain/repositories/home_repository.dart';

final homeMockDataSourceProvider = Provider<HomeMockDataSource>(
  (ref) => HomeMockDataSource(),
);

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepositoryImpl(ref.watch(homeMockDataSourceProvider)),
);

/// Drives the Home Feed screen. Swapping [HomeRepositoryImpl] for a Dio
/// backed implementation is the only change a real backend integration
/// requires.
final homeFeedProvider = FutureProvider<HomeFeedEntity>(
  (ref) => ref.watch(homeRepositoryProvider).getHomeFeed(),
);
