import '../daily_insight.dart';

/// [MockDailyInsightRepository] is wired as the default today; swap the
/// `dailyInsightRepositoryProvider` override to a Gemini-backed
/// implementation once that service exists — no widget changes required.
abstract class DailyInsightRepository {
  Future<DailyInsight> getTodaysInsight();
}
