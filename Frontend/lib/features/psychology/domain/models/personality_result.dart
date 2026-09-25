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
///
/// Timestamps:
/// - [completedAt] is when the *current* set of answers was completed. The
///   backend refreshes it on every submit that actually changes the answers
///   (an identical resubmission changes nothing), and counts the retake
///   cooldown from it — so [retakeHintAvailableAt] reads it, never
///   [updatedAt].
/// - [updatedAt] is general last-write metadata. It is never earlier than
///   [completedAt]; for responses saved before the backend began refreshing
///   [completedAt] it can be later. The "Updated {date}" label reads
///   [lastUpdatedAt] (the last write to the answers).
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

  /// The backend's *default* retake cooldown
  /// (`PSYCHOLOGY_RETAKE_COOLDOWN_DAYS`). The real value is server config
  /// and is not exposed, so anything derived from this is only a hint — a
  /// `429` with `retryAfterSeconds` from submit is the authority.
  static const defaultRetakeCooldown = Duration(days: 7);

  DateTime? get lastUpdatedAt => updatedAt ?? completedAt;

  /// Client-side estimate of when these answers can next be changed:
  /// [completedAt] + [cooldown]. Null when [completedAt] is unknown (then no
  /// hint is shown and the server decides on submit).
  DateTime? retakeHintAvailableAt({
    Duration cooldown = defaultRetakeCooldown,
  }) => completedAt?.add(cooldown);

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
