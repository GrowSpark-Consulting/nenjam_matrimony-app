import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  isPermissionKey,
  PERMISSIONS,
  SENSITIVE_PERMISSIONS,
} from './permissions';

/**
 * The code's permission registry and the keys seeded into the database must
 * be the same set, sensitivity included — a key only in code could never be
 * granted, and a key only in the database guards nothing.
 */
describe('permission registry', () => {
  const migrationsDir = join(
    __dirname,
    '../../../../../../libs/database/prisma/migrations',
  );

  function seededPermissions(): Map<string, boolean> {
    const seeded = new Map<string, boolean>();
    const row =
      /\(gen_random_uuid\(\)::text, '([a-z_.]+)', '(?:[^']|'')*', (true|false)\)/g;
    for (const dir of readdirSync(migrationsDir).sort()) {
      if (!/^\d{14}_/.test(dir)) continue;
      const sql = readFileSync(
        join(migrationsDir, dir, 'migration.sql'),
        'utf8',
      );
      const insert = sql.match(/INSERT INTO "permissions"[\s\S]*?;/g) ?? [];
      for (const statement of insert) {
        for (const [, key, sensitive] of statement.matchAll(row)) {
          seeded.set(key, sensitive === 'true');
        }
      }
    }
    return seeded;
  }

  it('matches the keys the migrations seed, sensitivity included', () => {
    const seeded = seededPermissions();
    expect([...seeded.keys()].sort()).toEqual([...PERMISSIONS].sort());
    for (const key of PERMISSIONS) {
      expect([key, seeded.get(key)]).toEqual([
        key,
        SENSITIVE_PERMISSIONS.has(key),
      ]);
    }
  });

  it('has no duplicates, and every key fits the database CHECK format', () => {
    expect(new Set(PERMISSIONS).size).toBe(PERMISSIONS.length);
    for (const key of PERMISSIONS) {
      expect(key).toMatch(/^[a-z]+(\.[a-z_]+)+$/);
    }
  });

  it('recognises only registered keys', () => {
    expect(isPermissionKey('agent.approve')).toBe(true);
    expect(isPermissionKey('agent.delete_everything')).toBe(false);
    expect(isPermissionKey('')).toBe(false);
  });
});
