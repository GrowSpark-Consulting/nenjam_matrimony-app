/// One selectable answer to a [QuizQuestion], as returned by
/// `GET /psychology/quiz/active`. The client submits [key]; [value] is
/// backend data only — it is parsed so the model mirrors the contract, but
/// the client never scores with it (all compatibility scoring is
/// server-side, pairwise).
class QuizOption {
  final String key;
  final String label;
  final int value;

  const QuizOption({
    required this.key,
    required this.label,
    required this.value,
  });

  factory QuizOption.fromJson(Map<String, dynamic> json) => QuizOption(
    key: json['key'] as String,
    label: json['label'] as String,
    value: (json['value'] as num?)?.toInt() ?? 0,
  );
}

/// A single single-select question of the active psychology quiz. The
/// backend deliberately never sends its scoring internals, and this model
/// has no place to hold them.
class QuizQuestion {
  final String id;
  final int order;
  final String dimension;
  final String questionText;
  final List<QuizOption> options;

  const QuizQuestion({
    required this.id,
    required this.order,
    required this.dimension,
    required this.questionText,
    this.options = const [],
  });

  /// Whether [key] is one of this question's options — used to drop a
  /// restored answer that no longer fits the question.
  bool hasOption(String key) => options.any((o) => o.key == key);

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
    id: json['id'] as String,
    order: (json['order'] as num?)?.toInt() ?? 0,
    dimension: json['dimension'] as String? ?? '',
    questionText: json['questionText'] as String,
    options: (json['options'] as List<dynamic>? ?? [])
        .map((e) => QuizOption.fromJson((e as Map).cast()))
        .toList(),
  );
}

/// The currently active quiz. [id] is whatever the backend returns — it is
/// what `POST /psychology/quiz/submit` must echo back, so it is never
/// hardcoded on the client.
class Quiz {
  final String id;
  final String title;
  final String? description;
  final String? version;
  final List<QuizQuestion> questions;

  const Quiz({
    required this.id,
    required this.title,
    this.description,
    this.version,
    this.questions = const [],
  });

  QuizQuestion? questionById(String id) {
    for (final q in questions) {
      if (q.id == id) return q;
    }
    return null;
  }

  factory Quiz.fromJson(Map<String, dynamic> json) {
    final questions =
        (json['questions'] as List<dynamic>? ?? [])
            .map((e) => QuizQuestion.fromJson((e as Map).cast()))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    return Quiz(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      version: json['version'] as String?,
      questions: questions,
    );
  }
}
