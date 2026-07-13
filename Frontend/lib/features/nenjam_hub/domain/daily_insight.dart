/// A single personalized, rotating insight shown on the Nenjam hub.
/// Mock-backed today; future-ready for a Gemini-driven service — see
/// [DailyInsightRepository].
class DailyInsight {
  final String message;

  const DailyInsight({required this.message});
}
