// Mapped from a Prisma UserProfilePrompt row (joined with its PromptBankItem)
// by PromptsRepository. promptText/category are denormalized from the join
// so the frontend gets a flat shape without a second lookup.
export class UserProfilePromptEntity {
  id!: string;
  promptId!: string;
  promptText!: string;
  category!: string;
  answerText!: string;
  order!: number;
}
