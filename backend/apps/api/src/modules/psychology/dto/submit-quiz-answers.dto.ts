import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsNotEmpty,
  IsString,
  MaxLength,
  ValidateNested,
} from 'class-validator';

export class QuizAnswerDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  questionId!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(20)
  selectedKey!: string;
}

// POST /psychology/quiz/submit body. `quizId` must be the currently active
// quiz's id — see PsychologyService.submitAnswers, which rejects a submission
// against a retired/mismatched quiz rather than silently accepting it against
// whatever quiz the caller thinks is active.
//
// Sizes are bounded: a quiz has a few dozen questions at most, so anything
// larger is malformed, and the per-item length caps keep the validation
// messages that echo caller input short.
export class SubmitQuizAnswersDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  quizId!: string;

  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(50)
  @ValidateNested({ each: true })
  @Type(() => QuizAnswerDto)
  answers!: QuizAnswerDto[];
}
