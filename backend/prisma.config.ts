import 'dotenv/config';
import { defineConfig, env } from 'prisma/config';

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
