import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/mock_daily_insight_repository.dart';
import '../../domain/daily_insight.dart';
import '../../domain/repositories/daily_insight_repository.dart';

/// Default implementation is the in-memory mock. Override this provider
/// with a Gemini-backed repository once that service is ready — no other
/// code needs to change.
final dailyInsightRepositoryProvider = Provider<DailyInsightRepository>(
  (ref) => MockDailyInsightRepository(),
);

final dailyInsightProvider = FutureProvider.autoDispose<DailyInsight>((ref) {
  return ref.watch(dailyInsightRepositoryProvider).getTodaysInsight();
});
