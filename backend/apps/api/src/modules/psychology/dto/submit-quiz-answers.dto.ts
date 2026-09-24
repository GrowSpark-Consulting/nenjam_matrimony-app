import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsString,
  ValidateNested,
} from 'class-validator';

export class QuizAnswerDto {
  @IsString()
  questionId!: string;

  @IsString()
  selectedKey!: string;
}

// POST /psychology/quiz/submit body. `quizId` must be the currently active
// quiz's id — see PsychologyService.submitAnswers, which rejects a submission
// against a retired/mismatched quiz rather than silently accepting it against
// whatever quiz the caller thinks is active.
export class SubmitQuizAnswersDto {
  @IsString()
  quizId!: string;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => QuizAnswerDto)
  answers!: QuizAnswerDto[];
}
