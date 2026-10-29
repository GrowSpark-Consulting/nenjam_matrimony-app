/**
 * Database-gated (see docs/agent-program/agent-prisma-db-tests.md): proves the
 * unique-violation reader against the REAL Prisma engine and Postgres, so the
 * recorded error shape in the default spec cannot drift from reality.
 */
import { readUniqueViolation } from './prisma-unique-violation';
import { openTestDatabase, freshTestDatabase } from './prisma-test-database';

const db = openTestDatabase();
const prisma = db.prisma;

afterAll(() => db.close());
beforeEach(() => freshTestDatabase(prisma));

const person = { name: 'Ravi', city: 'Madurai', state: 'Tamil Nadu' };

async function violationOf(write: () => Promise<unknown>) {
  try {
    await write();
  } catch (error) {
    return readUniqueViolation(error);
  }
  throw new Error('The write was expected to violate a unique constraint.');
}

describe('readUniqueViolation on the real engine', () => {
  beforeEach(async () => {
    await prisma.agent.create({
      data: { id: 'a1', phone: '+919000000001', phoneHash: 'v1:h1', ...person },
    });
    await prisma.referralCode.create({
      data: { id: 'c1', agentId: 'a1', code: 'NM7K2P9X', isPrimary: true },
    });
    await prisma.agentRefreshToken.create({
      data: {
        id: 't1',
        agentId: 'a1',
        tokenHash: 'th1',
        expiresAt: new Date(),
      },
    });
  });

  it.each([
    [
      'agents primary key',
      'agents_pkey',
      ['id'],
      { id: 'a1', phone: '+919000000002', phoneHash: 'v1:h2' },
    ],
    [
      'agents phone',
      'agents_phone_key',
      ['phone'],
      { id: 'a2', phone: '+919000000001', phoneHash: 'v1:h2' },
    ],
    [
      'agents phone hash',
      'agents_phone_hash_key',
      ['phone_hash'],
      { id: 'a2', phone: '+919000000002', phoneHash: 'v1:h1' },
    ],
  ])('%s', async (_label, constraint, fields, data) => {
    const found = await violationOf(() =>
      prisma.agent.create({ data: { ...data, ...person } }),
    );
    expect(found).toEqual({ constraint, fields });
  });

  it.each([
    [
      'referral code',
      'referral_codes_code_key',
      ['code'],
      { id: 'c2', code: 'NM7K2P9X', isPrimary: false },
    ],
    [
      'referral code primary key',
      'referral_codes_pkey',
      ['id'],
      { id: 'c1', code: 'NM7K2P9Y', isPrimary: false },
    ],
    [
      'second primary code (partial unique index)',
      'referral_codes_one_primary_per_agent_uq',
      ['agent_id'],
      { id: 'c3', code: 'NM7K2P9Y', isPrimary: true },
    ],
  ])('%s', async (_label, constraint, fields, data) => {
    const found = await violationOf(() =>
      prisma.referralCode.create({ data: { agentId: 'a1', ...data } }),
    );
    expect(found).toEqual({ constraint, fields });
  });

  it.each([
    [
      'refresh token hash',
      'agent_refresh_tokens_token_hash_key',
      ['token_hash'],
      { id: 't2', tokenHash: 'th1' },
    ],
    [
      'refresh token primary key',
      'agent_refresh_tokens_pkey',
      ['id'],
      { id: 't1', tokenHash: 'th2' },
    ],
  ])('%s', async (_label, constraint, fields, data) => {
    const found = await violationOf(() =>
      prisma.agentRefreshToken.create({
        data: { agentId: 'a1', expiresAt: new Date(), ...data },
      }),
    );
    expect(found).toEqual({ constraint, fields });
  });

  it('does not call a CHECK violation a unique violation', async () => {
    let caught: unknown;
    try {
      await prisma.referralCode.create({
        data: { id: 'c9', agentId: 'a1', code: 'XX' },
      });
    } catch (error) {
      caught = error;
    }
    expect(String(caught)).toMatch(/referral_codes_code_format_chk/);
    expect(readUniqueViolation(caught)).toBeNull();
  });
});
