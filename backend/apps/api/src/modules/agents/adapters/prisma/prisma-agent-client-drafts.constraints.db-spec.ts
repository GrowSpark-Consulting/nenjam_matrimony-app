/**
 * Database-gated (see docs/agent-program/agent-prisma-db-tests.md): the rules
 * of migration 20261103090000_agent_client_drafts that only the SQL enforces.
 * One open draft per agent and phone, the allowed status changes, the lock
 * after submit, delete only while DRAFT, no TRUNCATE, and every CHECK.
 *
 * Plain SQL on purpose: the rules must hold whatever code writes the rows.
 * Every refusal names the rule it expects (the constraint, or the trigger's
 * message), so a test cannot pass because some other rule refused instead.
 */
import { openTestDatabase, freshTestDatabase } from './prisma-test-database';

const db = openTestDatabase();
const prisma = db.prisma;

afterAll(() => db.close());

const DAY_MS = 24 * 60 * 60 * 1000;
const NOW = new Date('2026-11-03T06:00:00.000Z');
const LATER = new Date(NOW.getTime() + 14 * DAY_MS);

type Status =
  'DRAFT' | 'WAITING_FOR_CLIENT' | 'ACCEPTED' | 'REJECTED' | 'EXPIRED';

type Row = Record<string, string | Date | null>;

/** A row that satisfies every CHECK for its status. */
function rowFor(status: Status, overrides: Row = {}): Row {
  const open = status === 'DRAFT' || status === 'WAITING_FOR_CLIENT';
  return {
    id: `d-${status.toLowerCase()}`,
    agent_id: 'a1',
    status,
    phone_hash: 'v1:client-1',
    phone_sealed: open || status === 'REJECTED' ? 'sealed:phone' : null,
    phone_masked: '+91 98***210',
    display_name: 'Priya S.',
    details_sealed: open ? 'sealed:details' : null,
    expires_at: LATER,
    submitted_at: status === 'DRAFT' || status === 'EXPIRED' ? null : NOW,
    accepted_at: status === 'ACCEPTED' ? NOW : null,
    closed_at: status === 'REJECTED' || status === 'EXPIRED' ? NOW : null,
    closed_reason: status === 'EXPIRED' ? 'TIMED_OUT' : null,
    member_id: status === 'ACCEPTED' ? 'u1' : null,
    attribution_id: status === 'ACCEPTED' ? 'att1' : null,
    created_at: NOW,
    updated_at: NOW,
    ...overrides,
  };
}

async function insert(row: Row): Promise<void> {
  const columns = Object.keys(row);
  const values = columns.map((c, i) =>
    c === 'status' ? `$${i + 1}::"agent_client_draft_status"` : `$${i + 1}`,
  );
  await prisma.$executeRawUnsafe(
    `INSERT INTO "agent_client_drafts" (${columns
      .map((c) => `"${c}"`)
      .join(', ')}) VALUES (${values.join(', ')})`,
    ...columns.map((c) => row[c]),
  );
}

async function update(id: string, changes: Row): Promise<void> {
  const columns = Object.keys(changes);
  const sets = columns.map((c, i) =>
    c === 'status'
      ? `"status" = $${i + 2}::"agent_client_draft_status"`
      : `"${c}" = $${i + 2}`,
  );
  await prisma.$executeRawUnsafe(
    `UPDATE "agent_client_drafts" SET ${sets.join(', ')} WHERE "id" = $1`,
    id,
    ...columns.map((c) => changes[c]),
  );
}

async function remove(id: string): Promise<void> {
  await prisma.$executeRawUnsafe(
    `DELETE FROM "agent_client_drafts" WHERE "id" = $1`,
    id,
  );
}

async function statusOf(id: string): Promise<string | null> {
  const rows = await prisma.$queryRawUnsafe<Array<{ status: string }>>(
    `SELECT "status"::text AS status FROM "agent_client_drafts" WHERE "id" = $1`,
    id,
  );
  return rows[0]?.status ?? null;
}

/** The database's refusal as text (message and details), or a failure. */
async function refusal(write: () => Promise<unknown>): Promise<string> {
  try {
    await write();
  } catch (error) {
    const e = error as { message?: string; meta?: unknown };
    return `${e.message ?? ''} ${JSON.stringify(e.meta ?? {})}`;
  }
  throw new Error('The write was expected to be refused.');
}

/** What a row moving to `status` must look like, so only the rule under test can refuse it. */
const CLOSE: Record<Status, Row> = {
  DRAFT: {},
  WAITING_FOR_CLIENT: { submitted_at: NOW },
  ACCEPTED: {
    details_sealed: null,
    phone_sealed: null,
    accepted_at: NOW,
    member_id: 'u1',
    attribution_id: 'att1',
  },
  REJECTED: { details_sealed: null, closed_at: NOW },
  EXPIRED: {
    details_sealed: null,
    phone_sealed: null,
    closed_at: NOW,
    closed_reason: 'TIMED_OUT',
  },
};

beforeEach(async () => {
  await freshTestDatabase(prisma);
  const person = { city: 'Madurai', state: 'Tamil Nadu' };
  await prisma.agent.create({
    data: {
      id: 'a1',
      phone: '+919000000001',
      phoneHash: 'v1:a1',
      name: 'Ravi Kumar',
      ...person,
    },
  });
  await prisma.agent.create({
    data: {
      id: 'a2',
      phone: '+919000000002',
      phoneHash: 'v1:a2',
      name: 'Anu Raj',
      ...person,
    },
  });
  await prisma.user.create({
    data: {
      id: 'u1',
      firebaseUid: 'fb-u1',
      email: 'fb-u1@firebase.invalid',
      phone: '+919876543210',
    },
  });
  await prisma.user.create({
    data: {
      id: 'u2',
      firebaseUid: 'fb-u2',
      email: 'fb-u2@firebase.invalid',
      phone: '+919999999999',
    },
  });
  await prisma.referralAttribution.create({
    data: {
      id: 'att1',
      userId: 'u1',
      phoneHash: 'v1:client-1',
      agentId: 'a1',
      source: 'ADDED_BY_AGENT',
      windowEndsAt: LATER,
    },
  });
});

describe('agent_client_drafts: valid rows and changes', () => {
  it.each<[Status]>([
    ['DRAFT'],
    ['WAITING_FOR_CLIENT'],
    ['ACCEPTED'],
    ['REJECTED'],
    ['EXPIRED'],
  ])('a well-formed %s row is accepted', async (status) => {
    await insert(rowFor(status));
    expect(await statusOf(rowFor(status).id as string)).toBe(status);
  });

  it('DRAFT can be edited, then submitted, then accepted', async () => {
    await insert(rowFor('DRAFT', { id: 'd1' }));
    await update('d1', {
      display_name: 'Priya K.',
      details_sealed: 'sealed:v2',
      expires_at: LATER,
    });
    await update('d1', {
      status: 'WAITING_FOR_CLIENT',
      ...CLOSE.WAITING_FOR_CLIENT,
    });
    await update('d1', { status: 'ACCEPTED', ...CLOSE.ACCEPTED });
    expect(await statusOf('d1')).toBe('ACCEPTED');
  });

  it.each<[Status, Status]>([
    ['DRAFT', 'EXPIRED'],
    ['WAITING_FOR_CLIENT', 'REJECTED'],
    ['WAITING_FOR_CLIENT', 'EXPIRED'],
  ])('%s -> %s is allowed', async (from, to) => {
    await insert(rowFor(from, { id: 'd1' }));
    await update('d1', { status: to, ...CLOSE[to] });
    expect(await statusOf('d1')).toBe(to);
  });

  it('a DRAFT can be deleted (discarded)', async () => {
    await insert(rowFor('DRAFT', { id: 'd1' }));
    await remove('d1');
    expect(await statusOf('d1')).toBeNull();
  });

  it('deleting the member clears the link on an accepted draft (and nothing else)', async () => {
    await insert(rowFor('ACCEPTED', { id: 'd1' }));
    await prisma.referralAttribution.update({
      where: { id: 'att1' },
      data: { userId: null },
    });
    await prisma.user.delete({ where: { id: 'u1' } });
    const rows = await prisma.$queryRawUnsafe<
      Array<{ member_id: string | null; status: string }>
    >(
      `SELECT "member_id", "status"::text AS status FROM "agent_client_drafts" WHERE "id" = 'd1'`,
    );
    expect(rows).toEqual([{ member_id: null, status: 'ACCEPTED' }]);
  });
});

describe('agent_client_drafts: one open draft per agent and phone', () => {
  const RULE = /agent_client_drafts_one_open_per_agent_phone_uq/;

  it.each<[Status, Status]>([
    ['DRAFT', 'DRAFT'],
    ['DRAFT', 'WAITING_FOR_CLIENT'],
    ['WAITING_FOR_CLIENT', 'DRAFT'],
    ['WAITING_FOR_CLIENT', 'WAITING_FOR_CLIENT'],
  ])('an open %s refuses a second open %s', async (first, second) => {
    await insert(rowFor(first, { id: 'd1' }));
    expect(await refusal(() => insert(rowFor(second, { id: 'd2' })))).toMatch(
      RULE,
    );
  });

  it.each<[Status]>([['ACCEPTED'], ['REJECTED'], ['EXPIRED']])(
    'a closed %s draft does not count',
    async (closed) => {
      await insert(rowFor(closed, { id: 'd1' }));
      await insert(rowFor('DRAFT', { id: 'd2' }));
      expect(await statusOf('d2')).toBe('DRAFT');
    },
  );

  it('another agent, or another phone, may have its own open draft', async () => {
    await insert(rowFor('DRAFT', { id: 'd1' }));
    await insert(rowFor('DRAFT', { id: 'd2', agent_id: 'a2' }));
    await insert(rowFor('DRAFT', { id: 'd3', phone_hash: 'v1:client-2' }));
    expect(await statusOf('d3')).toBe('DRAFT');
  });
});

describe('agent_client_drafts: status changes', () => {
  const RULE = /is not allowed/;
  const REFUSED: Array<[Status, Status]> = [
    ['DRAFT', 'ACCEPTED'],
    ['DRAFT', 'REJECTED'],
    ['WAITING_FOR_CLIENT', 'DRAFT'],
    ['ACCEPTED', 'DRAFT'],
    ['ACCEPTED', 'WAITING_FOR_CLIENT'],
    ['ACCEPTED', 'REJECTED'],
    ['ACCEPTED', 'EXPIRED'],
    ['REJECTED', 'DRAFT'],
    ['REJECTED', 'WAITING_FOR_CLIENT'],
    ['REJECTED', 'ACCEPTED'],
    ['REJECTED', 'EXPIRED'],
    ['EXPIRED', 'DRAFT'],
    ['EXPIRED', 'WAITING_FOR_CLIENT'],
    ['EXPIRED', 'ACCEPTED'],
    ['EXPIRED', 'REJECTED'],
  ];

  it.each(REFUSED)('%s -> %s is refused', async (from, to) => {
    await insert(rowFor(from, { id: 'd1' }));
    const target = rowFor(to, { id: 'd1' });
    // Everything the target status needs, so only the transition rule refuses.
    const changes: Row = { ...target };
    for (const k of ['id', 'agent_id', 'phone_hash', 'created_at'])
      delete changes[k];
    expect(await refusal(() => update('d1', changes))).toMatch(RULE);
    expect(await statusOf('d1')).toBe(from);
  });

  it('accepting must name the member it created', async () => {
    await insert(rowFor('WAITING_FOR_CLIENT', { id: 'd1' }));
    expect(
      await refusal(() =>
        update('d1', {
          status: 'ACCEPTED',
          ...CLOSE.ACCEPTED,
          member_id: null,
        }),
      ),
    ).toMatch(/names the member it created/);
  });
});

describe('agent_client_drafts: what never changes', () => {
  it.each([
    ['agent_id', 'a2'],
    ['phone_hash', 'v1:client-2'],
    ['created_at', new Date(NOW.getTime() - DAY_MS)],
    ['id', 'd9'],
  ])('%s cannot change, even on a DRAFT', async (column, value) => {
    await insert(rowFor('DRAFT', { id: 'd1' }));
    expect(await refusal(() => update('d1', { [column]: value }))).toMatch(
      /id, agent_id, phone_hash and created_at never change/,
    );
  });
});

describe('agent_client_drafts: locked after submit', () => {
  it.each([
    ['display_name', 'Someone E.'],
    ['phone_masked', '+91 90***001'],
    ['details_sealed', 'sealed:changed'],
    ['phone_sealed', 'sealed:other-phone'],
    ['expires_at', new Date(LATER.getTime() + DAY_MS)],
    ['submitted_at', new Date(NOW.getTime() + 1000)],
  ])('a waiting draft refuses a change to %s', async (column, value) => {
    await insert(rowFor('WAITING_FOR_CLIENT', { id: 'd1' }));
    expect(await refusal(() => update('d1', { [column]: value }))).toMatch(
      /a submitted draft is locked/,
    );
  });

  it.each<[Status, string, string | Date]>([
    ['ACCEPTED', 'display_name', 'Someone E.'],
    ['ACCEPTED', 'accepted_at', new Date(NOW.getTime() + 1000)],
    ['ACCEPTED', 'member_id', 'u2'],
    ['REJECTED', 'phone_sealed', 'sealed:other-phone'],
    ['REJECTED', 'closed_at', new Date(NOW.getTime() + 1000)],
    ['EXPIRED', 'closed_reason', 'AGENT_TERMINATED'],
    ['EXPIRED', 'phone_masked', '+91 90***001'],
  ])('a %s draft refuses a change to %s', async (status, column, value) => {
    await insert(rowFor(status, { id: 'd1' }));
    expect(await refusal(() => update('d1', { [column]: value }))).toMatch(
      /a closed draft never changes/,
    );
  });
});

describe('agent_client_drafts: delete and TRUNCATE', () => {
  it.each<[Status]>([
    ['WAITING_FOR_CLIENT'],
    ['ACCEPTED'],
    ['REJECTED'],
    ['EXPIRED'],
  ])('a %s draft cannot be deleted', async (status) => {
    await insert(rowFor(status, { id: 'd1' }));
    expect(await refusal(() => remove('d1'))).toMatch(
      /only a DRAFT may be deleted/,
    );
    expect(await statusOf('d1')).toBe(status);
  });

  it('TRUNCATE is refused', async () => {
    await insert(rowFor('REJECTED', { id: 'd1' }));
    expect(
      await refusal(() =>
        prisma.$executeRawUnsafe('TRUNCATE "agent_client_drafts"'),
      ),
    ).toMatch(/holds client consent records/);
    expect(await statusOf('d1')).toBe('REJECTED');
  });
});

describe('agent_client_drafts: CHECKs', () => {
  it.each<[string, Status, Row]>([
    ['not_blank', 'DRAFT', { phone_hash: '  ' }],
    ['not_blank', 'DRAFT', { phone_masked: '' }],
    ['not_blank', 'DRAFT', { display_name: ' ' }],
    ['submitted', 'DRAFT', { submitted_at: NOW }],
    ['submitted', 'WAITING_FOR_CLIENT', { submitted_at: null }],
    ['submitted', 'ACCEPTED', { submitted_at: null }],
    ['submitted', 'REJECTED', { submitted_at: null }],
    ['accepted', 'ACCEPTED', { accepted_at: null }],
    ['accepted', 'ACCEPTED', { attribution_id: null }],
    ['only_accepted_links', 'DRAFT', { member_id: 'u1' }],
    ['only_accepted_links', 'WAITING_FOR_CLIENT', { attribution_id: 'att1' }],
    ['only_accepted_links', 'REJECTED', { accepted_at: NOW }],
    ['closed', 'REJECTED', { closed_at: null }],
    ['closed', 'EXPIRED', { closed_at: null }],
    ['closed', 'DRAFT', { closed_at: NOW }],
    ['closed', 'ACCEPTED', { closed_at: NOW }],
    ['closed_reason', 'EXPIRED', { closed_reason: null }],
    ['closed_reason', 'REJECTED', { closed_reason: 'TIMED_OUT' }],
    ['closed_reason_values', 'EXPIRED', { closed_reason: 'BORED' }],
    ['details', 'DRAFT', { details_sealed: null }],
    ['details', 'WAITING_FOR_CLIENT', { details_sealed: null }],
    ['details', 'ACCEPTED', { details_sealed: 'sealed:details' }],
    ['details', 'REJECTED', { details_sealed: 'sealed:details' }],
    ['details', 'EXPIRED', { details_sealed: 'sealed:details' }],
    ['phone_sealed', 'DRAFT', { phone_sealed: null }],
    ['phone_sealed', 'WAITING_FOR_CLIENT', { phone_sealed: null }],
    ['phone_sealed', 'REJECTED', { phone_sealed: null }],
    ['phone_sealed', 'ACCEPTED', { phone_sealed: 'sealed:phone' }],
    ['phone_sealed', 'EXPIRED', { phone_sealed: 'sealed:phone' }],
    ['expires', 'DRAFT', { expires_at: NOW }],
  ])('%s: a %s row with %j is refused', async (rule, status, overrides) => {
    expect(await refusal(() => insert(rowFor(status, overrides)))).toMatch(
      new RegExp(`agent_client_drafts_${rule}_chk`),
    );
  });

  it.each([
    'TIMED_OUT',
    'CLIENT_ACCEPTED_ANOTHER',
    'CLIENT_ALREADY_MEMBER',
    'AGENT_TERMINATED',
  ])('closed_reason %s is accepted on an EXPIRED draft', async (reason) => {
    await insert(rowFor('EXPIRED', { closed_reason: reason }));
    expect(await statusOf('d-expired')).toBe('EXPIRED');
  });

  it('an EXPIRED draft that was never submitted, or was, is accepted', async () => {
    await insert(rowFor('EXPIRED', { id: 'e1', submitted_at: null }));
    await insert(
      rowFor('EXPIRED', {
        id: 'e2',
        phone_hash: 'v1:client-2',
        submitted_at: NOW,
      }),
    );
    expect([await statusOf('e1'), await statusOf('e2')]).toEqual([
      'EXPIRED',
      'EXPIRED',
    ]);
  });
});

describe('agent_client_consent_codes', () => {
  const add = (phoneHash: string, challengeId: string) =>
    prisma.$executeRawUnsafe(
      `INSERT INTO "agent_client_consent_codes" ("phone_hash", "challenge_id", "expires_at") VALUES ($1, $2, $3)`,
      phoneHash,
      challengeId,
      LATER,
    );

  it('keeps one pointer per phone', async () => {
    await add('v1:client-1', 'ch-1');
    expect(await refusal(() => add('v1:client-1', 'ch-2'))).toMatch(
      /agent_client_consent_codes_pkey|phone_hash/,
    );
  });

  it.each([
    ['  ', 'ch-1'],
    ['v1:client-1', ''],
  ])(
    'refuses a blank phone hash or challenge id (%j, %j)',
    async (hash, id) => {
      expect(await refusal(() => add(hash, id))).toMatch(
        /agent_client_consent_codes_not_blank_chk/,
      );
    },
  );
});
