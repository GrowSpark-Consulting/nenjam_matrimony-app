import { BadRequestException } from '@nestjs/common';
import { PromptsRepository } from '../repositories/prompts.repository';
import { PromptsService } from '../services/prompts.service';
import { PromptBankItemEntity } from '../entities/prompt-bank-item.entity';
import { UserProfilePromptEntity } from '../entities/user-profile-prompt.entity';

function buildBankItem(
  overrides: Partial<PromptBankItemEntity> = {},
): PromptBankItemEntity {
  const entity = new PromptBankItemEntity();
  Object.assign(entity, {
    id: 'prompt-1',
    category: 'PERSONALITY',
    promptText: 'My perfect Sunday is…',
    order: 1,
    ...overrides,
  });
  return entity;
}

function buildUserPrompt(
  overrides: Partial<UserProfilePromptEntity> = {},
): UserProfilePromptEntity {
  const entity = new UserProfilePromptEntity();
  Object.assign(entity, {
    id: 'up-1',
    promptId: 'prompt-1',
    promptText: 'My perfect Sunday is…',
    category: 'PERSONALITY',
    answerText: 'Coffee and a long walk.',
    order: 0,
    ...overrides,
  });
  return entity;
}

describe('PromptsService', () => {
  function buildService(overrides?: {
    findBank?: jest.Mock;
    findUserPrompts?: jest.Mock;
    replaceUserPrompts?: jest.Mock;
    deleteUserPrompt?: jest.Mock;
  }) {
    const repository = {
      findBank:
        overrides?.findBank ?? jest.fn().mockResolvedValue([buildBankItem()]),
      findUserPrompts: overrides?.findUserPrompts ?? jest.fn(),
      replaceUserPrompts: overrides?.replaceUserPrompts ?? jest.fn(),
      deleteUserPrompt: overrides?.deleteUserPrompt ?? jest.fn(),
    } as unknown as PromptsRepository;

    return { service: new PromptsService(repository), repository };
  }

  it('getBank delegates to the repository', async () => {
    const bank = [buildBankItem()];
    const { service } = buildService({
      findBank: jest.fn().mockResolvedValue(bank),
    });

    await expect(service.getBank()).resolves.toBe(bank);
  });

  it('getUserPrompts delegates to the repository', async () => {
    const prompts = [buildUserPrompt()];
    const { service } = buildService({
      findUserPrompts: jest.fn().mockResolvedValue(prompts),
    });

    await expect(service.getUserPrompts('user-1')).resolves.toBe(prompts);
  });

  describe('saveUserPrompts', () => {
    it('rejects more than 3 prompts', async () => {
      const { service } = buildService();
      const answers = [
        { promptId: 'prompt-1', answerText: 'a' },
        { promptId: 'prompt-2', answerText: 'b' },
        { promptId: 'prompt-3', answerText: 'c' },
        { promptId: 'prompt-4', answerText: 'd' },
      ];

      await expect(service.saveUserPrompts('user-1', answers)).rejects.toThrow(
        BadRequestException,
      );
    });

    it('rejects duplicate promptId in the same submission', async () => {
      const { service } = buildService();
      const answers = [
        { promptId: 'prompt-1', answerText: 'a' },
        { promptId: 'prompt-1', answerText: 'b' },
      ];

      await expect(service.saveUserPrompts('user-1', answers)).rejects.toThrow(
        BadRequestException,
      );
    });

    it('rejects a promptId that is not in the active bank', async () => {
      const { service } = buildService({
        findBank: jest
          .fn()
          .mockResolvedValue([buildBankItem({ id: 'prompt-1' })]),
      });

      await expect(
        service.saveUserPrompts('user-1', [
          { promptId: 'does-not-exist', answerText: 'a' },
        ]),
      ).rejects.toThrow(BadRequestException);
    });

    it('does not check the bank when the submission is empty (clearing all prompts)', async () => {
      const findBank = jest.fn().mockResolvedValue([buildBankItem()]);
      const replaceUserPrompts = jest.fn().mockResolvedValue([]);
      const { service } = buildService({ findBank, replaceUserPrompts });

      await service.saveUserPrompts('user-1', []);

      expect(findBank).not.toHaveBeenCalled();
      expect(replaceUserPrompts).toHaveBeenCalledWith('user-1', []);
    });

    it('saves valid, non-duplicate prompt ids within the bank', async () => {
      const replaceUserPrompts = jest
        .fn()
        .mockResolvedValue([buildUserPrompt()]);
      const { service } = buildService({
        findBank: jest
          .fn()
          .mockResolvedValue([
            buildBankItem({ id: 'prompt-1' }),
            buildBankItem({ id: 'prompt-2' }),
          ]),
        replaceUserPrompts,
      });

      const answers = [
        { promptId: 'prompt-1', answerText: 'a' },
        { promptId: 'prompt-2', answerText: 'b' },
      ];
      await service.saveUserPrompts('user-1', answers);

      expect(replaceUserPrompts).toHaveBeenCalledWith('user-1', answers);
    });
  });

  describe('deletePrompt', () => {
    it('delegates to the repository', async () => {
      const deleteUserPrompt = jest.fn().mockResolvedValue(undefined);
      const { service } = buildService({ deleteUserPrompt });

      await service.deletePrompt('user-1', 'prompt-1');

      expect(deleteUserPrompt).toHaveBeenCalledWith('user-1', 'prompt-1');
    });
  });
});
