/// OCEAN Big-Five personality result. Scores are 0-100.
class PersonalityResult {
  final bool completed;
  final DateTime? completedAt;
  final int openness;
  final int conscientiousness;
  final int extraversion;
  final int agreeableness;
  final int neuroticism;

  const PersonalityResult({
    this.completed = false,
    this.completedAt,
    this.openness = 0,
    this.conscientiousness = 0,
    this.extraversion = 0,
    this.agreeableness = 0,
    this.neuroticism = 0,
  });

  /// Friendlier, user-facing framing of Neuroticism — higher is better
  /// (more emotionally balanced), unlike the raw trait it inverts.
  int get emotionalBalance => 100 - neuroticism;
}
