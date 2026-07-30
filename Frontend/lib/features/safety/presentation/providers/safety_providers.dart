import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_providers.dart';
import '../../data/repositories/safety_repository_impl.dart';
import '../../domain/repositories/safety_repository.dart';

final safetyRepositoryProvider = Provider<SafetyRepository>(
  (ref) => SafetyRepositoryImpl(ref.watch(apiClientProvider)),
);
