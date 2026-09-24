/// One saved answer from `GET /psychology/quiz/me` (and the submit
/// response). [questionText]/[selectedLabel] are read-time labels the
/// backend joins in for display; [selectedKey] is the stored answer.
class PsychologyQuizAnswer {
  final String questionId;
  final String dimension;
  final String questionText;
  final String selectedKey;
  final String selectedLabel;

  const PsychologyQuizAnswer({
    required this.questionId,
    required this.dimension,
    required this.questionText,
    required this.selectedKey,
    required this.selectedLabel,
  });

  factory PsychologyQuizAnswer.fromJson(Map<String, dynamic> json) =>
      PsychologyQuizAnswer(
        questionId: json['questionId'] as String,
        dimension: json['dimension'] as String? ?? '',
        questionText: json['questionText'] as String? ?? '',
        selectedKey: json['selectedKey'] as String,
        selectedLabel: json['selectedLabel'] as String? ?? '',
      );
}

/// The signed-in user's saved response to the active psychology quiz.
///
/// This is answers only — the backend scores this quiz pairwise against a
/// match, so there is no single-user result (no score, no traits) to show.
/// A retake overwrites the answers in place and moves [updatedAt]; the
/// backend leaves [completedAt] at the first submission, so "last taken"
/// UI reads [lastUpdatedAt].
class PsychologyQuizResponse {
  final String quizId;
  final List<PsychologyQuizAnswer> answers;
  final DateTime? completedAt;
  final DateTime? updatedAt;

  const PsychologyQuizResponse({
    required this.quizId,
    this.answers = const [],
    this.completedAt,
    this.updatedAt,
  });

  DateTime? get lastUpdatedAt => updatedAt ?? completedAt;

  /// questionId -> selectedKey, for pre-filling a retake.
  Map<String, String> get selectedKeys => {
    for (final a in answers) a.questionId: a.selectedKey,
  };

  factory PsychologyQuizResponse.fromJson(Map<String, dynamic> json) =>
      PsychologyQuizResponse(
        quizId: json['quizId'] as String,
        answers: (json['answers'] as List<dynamic>? ?? [])
            .map((e) => PsychologyQuizAnswer.fromJson((e as Map).cast()))
            .toList(),
        completedAt: _date(json['completedAt']),
        updatedAt: _date(json['updatedAt']),
      );

  static DateTime? _date(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;
}
