import { AgentConflictError } from '../../ports/agent-data-ports';
import {
  mapUniqueViolation,
  readUniqueViolation,
  withConflictMapping,
  type UniqueViolationRule,
} from './prisma-unique-violation';

/** The shape the real engine produced (recorded from the local Postgres run). */
const realEngineP2002 = (constraint: string, fields: string[]) => ({
  name: 'PrismaClientKnownRequestError',
  code: 'P2002',
  meta: {
    modelName: 'Agent',
    driverAdapterError: {
      name: 'DriverAdapterError',
      cause: {
        originalCode: '23505',
        originalMessage: `duplicate key value violates unique constraint "${constraint}"`,
        kind: 'UniqueConstraintViolation',
        constraint: { fields },
      },
    },
  },
});

const RULES: UniqueViolationRule[] = [
  {
    constraint: 'agents_phone_key',
    fields: ['phone'],
    reason: 'DUPLICATE_PHONE_HASH',
  },
  {
    constraint: 'agents_phone_hash_key',
    fields: ['phone_hash'],
    reason: 'DUPLICATE_PHONE_HASH',
  },
  { constraint: 'agents_pkey', fields: ['id'], reason: 'DUPLICATE_ID' },
];

describe('readUniqueViolation', () => {
  it('reads the columns and the constraint name from the driver-adapter shape', () => {
    expect(
      readUniqueViolation(
        realEngineP2002('agents_phone_hash_key', ['phone_hash']),
      ),
    ).toEqual({ fields: ['phone_hash'], constraint: 'agents_phone_hash_key' });
  });

  it('reads the classic meta.target (array or string) when there is no adapter detail', () => {
    expect(
      readUniqueViolation({ code: 'P2002', meta: { target: ['phone', 'x'] } }),
    ).toEqual({ fields: ['phone', 'x'], constraint: null });
    expect(
      readUniqueViolation({
        code: 'P2002',
        meta: { target: 'agents_phone_key' },
      }),
    ).toEqual({ fields: ['agents_phone_key'], constraint: null });
  });

  it('reads a bare driver-adapter unique error (no P2002 wrapper)', () => {
    expect(
      readUniqueViolation({
        name: 'DriverAdapterError',
        cause: {
          kind: 'UniqueConstraintViolation',
          constraint: { fields: ['code'] },
        },
      }),
    ).toEqual({ fields: ['code'], constraint: null });
  });

  it.each([
    ['null', null],
    ['a string', 'boom'],
    ['an ordinary Error', new Error('boom')],
    ['another Prisma code', { code: 'P2025', meta: {} }],
    [
      'a check violation',
      {
        name: 'DriverAdapterError',
        cause: { kind: 'postgres', originalCode: '23514' },
      },
    ],
  ])('returns null for %s', (_label, error) => {
    expect(readUniqueViolation(error)).toBeNull();
  });
});

describe('mapUniqueViolation', () => {
  it.each([
    ['agents_phone_key', ['phone'], 'DUPLICATE_PHONE_HASH'],
    ['agents_phone_hash_key', ['phone_hash'], 'DUPLICATE_PHONE_HASH'],
    ['agents_pkey', ['id'], 'DUPLICATE_ID'],
  ])('maps %s to %s', (constraint, fields, reason) => {
    const mapped = mapUniqueViolation(
      realEngineP2002(constraint, fields),
      RULES,
    );
    expect(mapped).toBeInstanceOf(AgentConflictError);
    expect(mapped?.reason).toBe(reason);
  });

  it('falls back to the columns when the constraint name is not available', () => {
    expect(
      mapUniqueViolation(
        { code: 'P2002', meta: { target: ['phone_hash'] } },
        RULES,
      )?.reason,
    ).toBe('DUPLICATE_PHONE_HASH');
  });

  it('prefers the constraint name over the columns', () => {
    // Same column, a constraint that no rule names: not ours, so not mapped.
    expect(
      mapUniqueViolation(
        realEngineP2002('some_other_key', ['phone_hash']),
        RULES,
      ),
    ).toBeNull();
  });

  it('does not map a unique violation that no rule describes', () => {
    expect(
      mapUniqueViolation(realEngineP2002('nope', ['nope']), RULES),
    ).toBeNull();
  });
});

describe('withConflictMapping', () => {
  it('returns the result when nothing fails', async () => {
    await expect(
      withConflictMapping(RULES, () => Promise.resolve(7)),
    ).resolves.toBe(7);
  });

  it('throws the mapped conflict for a described violation', async () => {
    await expect(
      withConflictMapping(RULES, () =>
        Promise.reject(
          realEngineP2002('agents_pkey', ['id']) as unknown as Error,
        ),
      ),
    ).rejects.toEqual(new AgentConflictError('DUPLICATE_ID'));
  });

  it('rethrows any other error unchanged', async () => {
    const boom = new Error('boom');
    await expect(
      withConflictMapping(RULES, () => Promise.reject(boom)),
    ).rejects.toBe(boom);
    const unknown = realEngineP2002('nope', ['nope']);
    await expect(
      withConflictMapping(RULES, () =>
        Promise.reject(unknown as unknown as Error),
      ),
    ).rejects.toBe(unknown);
  });
});
