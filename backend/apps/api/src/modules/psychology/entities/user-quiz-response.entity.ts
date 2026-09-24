// `answers` on UserQuizResponse ({ questionId: selectedOptionKey }) stays the
// single canonical record of what the user submitted — this entity only adds
// read-time labels (dimension/questionText/selectedLabel) by joining against
// the quiz's questions, it does not introduce a second stored representation.
export class UserQuizAnswerEntity {
  questionId!: string;
  dimension!: string;
  questionText!: string;
  selectedKey!: string;
  selectedLabel!: string;
}

export class UserQuizResponseEntity {
  quizId!: string;
  answers!: UserQuizAnswerEntity[];
  completedAt!: Date;
  updatedAt!: Date;
}
