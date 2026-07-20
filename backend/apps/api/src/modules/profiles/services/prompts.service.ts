import { BadRequestException, Injectable } from '@nestjs/common';
import { PromptsRepository } from '../repositories/prompts.repository';
import { PromptBankItemEntity } from '../entities/prompt-bank-item.entity';
import { UserProfilePromptEntity } from '../entities/user-profile-prompt.entity';
import { PromptAnswerDto } from '../dto/save-prompts.dto';

const MAX_PROMPTS_PER_USER = 3;

@Injectable()
export class PromptsService {
  constructor(private readonly promptsRepository: PromptsRepository) {}

  getBank(): Promise<PromptBankItemEntity[]> {
    return this.promptsRepository.findBank();
  }

  getUserPrompts(userId: string): Promise<UserProfilePromptEntity[]> {
    return this.promptsRepository.findUserPrompts(userId);
  }

  async saveUserPrompts(
    userId: string,
    answers: PromptAnswerDto[],
  ): Promise<UserProfilePromptEntity[]> {
    if (answers.length > MAX_PROMPTS_PER_USER) {
      throw new BadRequestException(
        `Cannot save more than ${MAX_PROMPTS_PER_USER} prompts.`,
      );
    }

    const promptIds = answers.map((a) => a.promptId);
    if (new Set(promptIds).size !== promptIds.length) {
      throw new BadRequestException(
        'The same prompt was submitted more than once.',
      );
    }

    if (promptIds.length > 0) {
      const bank = await this.promptsRepository.findBank();
      const validIds = new Set(bank.map((b) => b.id));
      const unknown = promptIds.filter((id) => !validIds.has(id));
      if (unknown.length > 0) {
        throw new BadRequestException(
          `Unknown prompt id(s): ${unknown.join(', ')}`,
        );
      }
    }

    return this.promptsRepository.replaceUserPrompts(userId, answers);
  }

  async deletePrompt(userId: string, promptId: string): Promise<void> {
    await this.promptsRepository.deleteUserPrompt(userId, promptId);
  }
}
