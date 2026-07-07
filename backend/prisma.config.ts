import { config } from 'dotenv';
import { defineConfig, env } from 'prisma/config';

// Match the precedence used by AppConfigModule (libs/config): .env is the
// committed base, .env.local (gitignored) holds real per-machine secrets and
// must win. Plain `import 'dotenv/config'` only loads .env and silently
// ignores .env.local, which caused Prisma CLI to authenticate with the
// placeholder password instead of the real one — confirmed by a P1000 error
// while a raw pg client with the same real credentials connected fine.
config({ path: '.env' });
config({ path: '.env.local', override: true });

export default defineConfig({
  schema: 'libs/database/prisma/schema.prisma',
  migrations: {
    path: 'libs/database/prisma/migrations',
    seed: 'ts-node libs/database/src/seed.ts',
  },
  datasource: {
    url: env('DATABASE_URL'),
  },
});
