import '../domain/daily_insight.dart';
import '../domain/repositories/daily_insight_repository.dart';

/// In-memory mock — no network calls. Default implementation until a
/// Gemini-backed service ships (see [DailyInsightRepository]).
class MockDailyInsightRepository implements DailyInsightRepository {
  static const _insights = [
    'You communicate best with calm, steady personalities.',
    'Profiles with similar family values respond to you more often.',
    'Your strongest compatibility this week comes from shared life goals.',
    'Completing your Psychology Assessment tends to sharpen your matches.',
    'Members who finish their horoscope details get noticeably more interest from you.',
    'Profiles who share your outlook on family tend to reply the fastest.',
    'Your profile draws the most interest from calm, family-oriented matches.',
  ];

  @override
  Future<DailyInsight> getTodaysInsight() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final dayIndex = DateTime.now().difference(DateTime(2024, 1, 1)).inDays;
    return DailyInsight(message: _insights[dayIndex % _insights.length]);
  }
}
