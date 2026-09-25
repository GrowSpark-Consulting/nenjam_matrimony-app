/**
 * Entrypoint for `pnpm seed:quiz`.
 *
 * Seeds ONLY the Marriage Compatibility Quiz (psychology_quizzes +
 * quiz_questions). Use this, not `pnpm db:seed`, to put the quiz into an
 * environment: the full seed also runs the plans, prompt-bank and default-admin
 * seeders, which have no business running against production just to get a
 * questionnaire.
 *
 * Idempotent and additive: upserts by id, never deletes, never reads or writes
 * user_quiz_responses, and never changes whether the quiz is active once it
 * exists (see seedQuiz).
 */
import { config } from 'dotenv';
import { PrismaPg } from '@prisma/adapter-pg';

config({ path: '.env' });
config({ path: '.env.local', override: true });

import { PrismaClient } from '../generated/client';
import { seedQuiz } from './seeders/quiz.seeder';
import { describeTarget } from './seeders/fake-profiles/seed-guard';

async function main(): Promise<void> {
  const databaseUrl = process.env.DATABASE_URL?.trim();
  if (!databaseUrl) throw new Error('DATABASE_URL is not set.');
  const target = describeTarget(databaseUrl);

  console.log('');
  console.log('========================================');
  console.log('PSYCHOLOGY QUIZ SEED');
  console.log('========================================');
  console.log(`Target : ${target.host} [${target.region}]`);

  const prisma = new PrismaClient({
    adapter: new PrismaPg({ connectionString: databaseUrl }),
  });

  try {
    await seedQuiz(prisma);
    console.log('');
    console.log('Quiz seed complete.');
    console.log('');
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  console.error('');
  console.error('PSYCHOLOGY QUIZ SEED FAILED');
  console.error('========================================');
  console.error(error instanceof Error ? error.message : error);
  console.error('');
  process.exit(1);
});
