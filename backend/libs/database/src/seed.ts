import { config } from 'dotenv';
import { PrismaPg } from '@prisma/adapter-pg';

// Same precedence as AppConfigModule and prisma.config.ts:
// .env.local (gitignored, real secrets) must override .env (committed, placeholders).
config({ path: '.env' });
config({ path: '.env.local', override: true });

import { PrismaClient } from '../generated/client';
import { seedPlans } from './seeders/plans.seeder';
import { seedQuiz } from './seeders/quiz.seeder';
import { seedAdmin } from './seeders/admin.seeder';

// ─────────────────────────────────────────────────────────────
// Bootstrap Prisma with the driver adapter (mirrors PrismaService)
// ─────────────────────────────────────────────────────────────
const prisma = new PrismaClient({
  adapter: new PrismaPg({
    host: process.env.DATABASE_HOST ?? 'localhost',
    port: Number(process.env.DATABASE_PORT ?? 5432),
    user: process.env.DATABASE_USER ?? 'postgres',
    password: process.env.DATABASE_PASSWORD ?? '',
    database: process.env.DATABASE_NAME ?? 'nenjam_matrimony',
  }),
});

// ─────────────────────────────────────────────────────────────
// Main seeder — runs all three sub-seeders in dependency order:
//   1. Plans          (no dependencies)
//   2. Quiz           (no dependencies)
//   3. Admin account  (no dependencies, but needs User table)
// ─────────────────────────────────────────────────────────────
async function main(): Promise<void> {
  console.log('');
  console.log('═══════════════════════════════════════════════════════');
  console.log('  Nenjam Matrimony — Database Seeder');
  console.log('  Environment :', process.env.NODE_ENV ?? 'development');
  console.log(
    '  Database    :',
    process.env.DATABASE_NAME ?? 'nenjam_matrimony',
  );
  console.log('═══════════════════════════════════════════════════════');

  // 1. Subscription plans
  await seedPlans(prisma);

  // 2. OCEAN psychology quiz
  await seedQuiz(prisma);

  // 3. Default admin account
  await seedAdmin(prisma);

  console.log('');
  console.log('═══════════════════════════════════════════════════════');
  console.log('  ✅  All seeders completed successfully.');
  console.log('═══════════════════════════════════════════════════════');
  console.log('');
}

main()
  .catch((error: unknown) => {
    console.error('\n❌  Seed failed:', error);
    process.exitCode = 1;
  })
  .finally(() => {
    void prisma.$disconnect();
  });
