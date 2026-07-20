import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsString,
  MaxLength,
  ValidateNested,
} from 'class-validator';

// Mirrors Frontend's PromptAnswer + AnswerPromptPage's 150-char limit.
export class PromptAnswerDto {
  @IsString()
  promptId!: string;

  @IsString()
  @MaxLength(150)
  answerText!: string;
}

// PUT /profiles/prompts/me — replace-all save, matching ChoosePromptPage's
// batch-selection UX (not one PATCH per prompt).
export class SavePromptsDto {
  @IsArray()
  @ArrayMaxSize(3)
  @ValidateNested({ each: true })
  @Type(() => PromptAnswerDto)
  prompts!: PromptAnswerDto[];
}
