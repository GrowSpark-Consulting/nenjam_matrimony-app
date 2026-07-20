import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type {
  PromptBankItem,
  UserProfilePrompt,
} from '../../../../../../libs/database/generated/client';
import { PromptBankItemEntity } from '../entities/prompt-bank-item.entity';
import { UserProfilePromptEntity } from '../entities/user-profile-prompt.entity';

@Injectable()
export class PromptsRepository {
  constructor(private readonly prisma: PrismaService) {}

  async findBank(): Promise<PromptBankItemEntity[]> {
    const rows = await this.prisma.promptBankItem.findMany({
      where: { isActive: true },
      orderBy: { order: 'asc' },
    });
    return rows.map((row) => this.toBankEntity(row));
  }

  async findUserPrompts(userId: string): Promise<UserProfilePromptEntity[]> {
    const rows = await this.prisma.userProfilePrompt.findMany({
      where: { userId },
      include: { prompt: true },
      orderBy: { order: 'asc' },
    });
    return rows.map((row) => this.toUserPromptEntity(row));
  }

  // Replace-all, not per-row update — order/count change on every save and
  // there's no natural per-row update key on the client side (ChoosePromptPage
  // always submits its full current selection). Runs as one transaction so a
  // failed create can't leave the user with zero saved prompts.
  async replaceUserPrompts(
    userId: string,
    answers: { promptId: string; answerText: string }[],
  ): Promise<UserProfilePromptEntity[]> {
    await this.prisma.$transaction([
      this.prisma.userProfilePrompt.deleteMany({ where: { userId } }),
      ...answers.map((a, index) =>
        this.prisma.userProfilePrompt.create({
          data: {
            userId,
            promptId: a.promptId,
            answerText: a.answerText,
            order: index,
          },
        }),
      ),
    ]);
    return this.findUserPrompts(userId);
  }

  async deleteUserPrompt(userId: string, promptId: string): Promise<void> {
    const result = await this.prisma.userProfilePrompt.deleteMany({
      where: { userId, promptId },
    });
    if (result.count === 0) {
      throw new NotFoundException('Prompt answer not found.');
    }
  }

  private toBankEntity(row: PromptBankItem): PromptBankItemEntity {
    const entity = new PromptBankItemEntity();
    Object.assign(entity, row);
    return entity;
  }

  private toUserPromptEntity(
    row: UserProfilePrompt & { prompt: PromptBankItem },
  ): UserProfilePromptEntity {
    const entity = new UserProfilePromptEntity();
    Object.assign(entity, {
      id: row.id,
      promptId: row.promptId,
      promptText: row.prompt.promptText,
      category: row.prompt.category,
      answerText: row.answerText,
      order: row.order,
    });
    return entity;
  }
}
