// Public shape of a quiz question — deliberately excludes `scoringType` and
// `pairRules`. pairRules in particular encodes which answer PAIRS trigger a
// flag/dealbreaker; shipping it to the client would let someone reverse-
// engineer which answer to pick to avoid a flag, so it never leaves the
// server. Mapped from Prisma's QuizQuestion row by PsychologyRepository.
export class QuizOptionEntity {
  key!: string;
  label!: string;
  value!: number;
}

export class QuizQuestionEntity {
  id!: string;
  order!: number;
  dimension!: string;
  questionText!: string;
  options!: QuizOptionEntity[];
}

export class ActiveQuizEntity {
  id!: string;
  title!: string;
  description!: string | null;
  version!: string;
  questions!: QuizQuestionEntity[];
}
