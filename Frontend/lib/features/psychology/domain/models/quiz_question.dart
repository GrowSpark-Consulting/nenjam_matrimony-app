/// A single OCEAN Big-Five quiz question, as returned by
/// `GET /psychology/quiz/active`. `reverseScored` is never sent by the
/// backend — scoring happens server-side.
class QuizQuestion {
  final String id;
  final String oceanDomain; // 'O' | 'C' | 'E' | 'A' | 'N'
  final String questionText;
  final int order;

  const QuizQuestion({
    required this.id,
    required this.oceanDomain,
    required this.questionText,
    required this.order,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) => QuizQuestion(
        id: json['id'] as String,
        oceanDomain: json['oceanDomain'] as String,
        questionText: json['questionText'] as String,
        order: (json['order'] as num).toInt(),
      );
}

class Quiz {
  final String id;
  final String title;
  final String? description;
  final List<QuizQuestion> questions;

  const Quiz({
    required this.id,
    required this.title,
    this.description,
    this.questions = const [],
  });

  factory Quiz.fromJson(Map<String, dynamic> json) => Quiz(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        questions: (json['questions'] as List<dynamic>? ?? [])
            .map((e) => QuizQuestion.fromJson((e as Map).cast()))
            .toList(),
      );
}
