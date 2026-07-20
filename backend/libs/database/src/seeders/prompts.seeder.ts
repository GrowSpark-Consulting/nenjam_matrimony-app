import { PromptCategory, PrismaClient } from '../../generated/client';

// Mirrors Frontend/lib/features/profile_prompts/data/repositories/
// mock_profile_prompt_repository.dart's hardcoded bank exactly, so the
// catalog a user sees doesn't change when the frontend flips from the mock
// repository to this real one.
interface PromptDefinition {
  id: string;
  category: PromptCategory;
  promptText: string;
  order: number;
}

const PROMPTS: PromptDefinition[] = [
  // ── Personality ──────────────────────────────────────────
  {
    id: 'prompt-p1-seed',
    category: PromptCategory.PERSONALITY,
    promptText: "People say I'm the go-to person for…",
    order: 1,
  },
  {
    id: 'prompt-p2-seed',
    category: PromptCategory.PERSONALITY,
    promptText: 'One thing that always makes me smile…',
    order: 2,
  },
  {
    id: 'prompt-p3-seed',
    category: PromptCategory.PERSONALITY,
    promptText: 'My most unusual talent…',
    order: 3,
  },
  {
    id: 'prompt-p4-seed',
    category: PromptCategory.PERSONALITY,
    promptText: 'I am happiest when…',
    order: 4,
  },
  {
    id: 'prompt-p5-seed',
    category: PromptCategory.PERSONALITY,
    promptText: 'My perfect Sunday is…',
    order: 5,
  },

  // ── Marriage & Compatibility ─────────────────────────────
  {
    id: 'prompt-m1-seed',
    category: PromptCategory.MARRIAGE_COMPATIBILITY,
    promptText: 'My idea of marriage is…',
    order: 6,
  },
  {
    id: 'prompt-m2-seed',
    category: PromptCategory.MARRIAGE_COMPATIBILITY,
    promptText: 'A relationship works best when…',
    order: 7,
  },
  {
    id: 'prompt-m3-seed',
    category: PromptCategory.MARRIAGE_COMPATIBILITY,
    promptText: 'I value my partner because…',
    order: 8,
  },

  // ── Family ────────────────────────────────────────────────
  {
    id: 'prompt-f1-seed',
    category: PromptCategory.FAMILY,
    promptText: 'My family describes me as…',
    order: 9,
  },
  {
    id: 'prompt-f2-seed',
    category: PromptCategory.FAMILY,
    promptText: 'Family traditions I love…',
    order: 10,
  },

  // ── Career ────────────────────────────────────────────────
  {
    id: 'prompt-c1-seed',
    category: PromptCategory.CAREER,
    promptText: 'My biggest ambition is…',
    order: 11,
  },
  {
    id: 'prompt-c2-seed',
    category: PromptCategory.CAREER,
    promptText: 'Work-life balance means…',
    order: 12,
  },
];

/**
 * Seeds the prompt_bank_items table. Safe to re-run: uses upsert so
 * existing data is not duplicated.
 */
export async function seedPrompts(prisma: PrismaClient): Promise<void> {
  console.log('\n💬  Seeding profile prompt bank…');

  let upsertCount = 0;
  for (const p of PROMPTS) {
    await prisma.promptBankItem.upsert({
      where: { id: p.id },
      update: {
        category: p.category,
        promptText: p.promptText,
        order: p.order,
        isActive: true,
      },
      create: {
        id: p.id,
        category: p.category,
        promptText: p.promptText,
        order: p.order,
        isActive: true,
      },
    });
    upsertCount++;
  }

  console.log(`  ✅  ${upsertCount} prompts seeded successfully.`);
}
