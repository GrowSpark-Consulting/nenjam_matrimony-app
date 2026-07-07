import { config } from 'dotenv';
import { PrismaPg } from '@prisma/adapter-pg';

// Same precedence as AppConfigModule and prisma.config.ts: .env.local
// (gitignored, real secrets) must override .env (committed, placeholders).
config({ path: '.env' });
config({ path: '.env.local', override: true });
import { PrismaClient } from '../generated/client';

const prisma = new PrismaClient({
  adapter: new PrismaPg({
    host: process.env.DATABASE_HOST ?? 'localhost',
    port: Number(process.env.DATABASE_PORT ?? 5432),
    user: process.env.DATABASE_USER ?? 'postgres',
    password: process.env.DATABASE_PASSWORD ?? '',
    database: process.env.DATABASE_NAME ?? 'app',
  }),
});

async function main(): Promise<void> {
  const user = await prisma.user.upsert({
    where: { email: 'admin@example.com' },
    update: {},
    create: { email: 'admin@example.com' },
  });

  console.log('Seeded user:', user);
}

main()
  .catch((error: unknown) => {
    console.error('Seed failed:', error);
    process.exitCode = 1;
  })
  .finally(() => {
    void prisma.$disconnect();
  });
