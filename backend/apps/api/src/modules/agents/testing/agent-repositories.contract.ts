/**
 * One behaviour suite for the agent repositories and the unit of work, run
 * against BOTH the in-memory fakes (default `pnpm test`) and the Prisma
 * adapters (database-gated, `pnpm test:agent-db`). If the two ever disagree,
 * one of them is wrong, and a service tested on the fakes may not behave the
 * same on the real database.
 *
 * Only behaviour both must show is here. Things only a real database can do
 * (a foreign key, a CHECK, the same phone under another hash) are tested in
 * the Prisma-only specs.
 */
import {
  AgentConflictError,
  type AgentRecord,
  type AgentRefreshTokenRecord,
  type AgentRefreshTokenRepository,
  type AgentRepository,
  type AgentPayoutDetailsRepository,
  type ReferralCodeRecord,
  type ReferralCodeRepository,
} from '../ports/agent-data-ports';
import type { AgentAuditPort } from '../ports/agent-platform-ports';
import type { AgentUnitOfWork } from '../ports/agent-unit-of-work.port';

export interface AgentContractWorld {
  uow: AgentUnitOfWork;
  agents: AgentRepository;
  codes: ReferralCodeRepository;
  tokens: AgentRefreshTokenRepository;
  payout: AgentPayoutDetailsRepository;
  audit: AgentAuditPort;
  /** How many audit rows exist right now. */
  auditCount(): Promise<number>;
  /** Called after each test; the Prisma world empties its tables here. */
  cleanup?(): Promise<void>;
}

/** Whole milliseconds: the database column keeps milliseconds. */
const T0 = new Date('2026-10-29T09:00:00.000Z');
const at = (minutes: number) => new Date(T0.getTime() + minutes * 60_000);

const newAgent = (n: number) => ({
  id: `agent-${n}`,
  phoneHash: `v1:hash-${n}`,
  phoneE164: `+91900000000${n}`,
  name: `Agent ${n}`,
  city: 'Madurai',
  state: 'Tamil Nadu',
  panLast4: null,
  panSealed: null,
  createdAt: at(0),
});

const code = (
  n: number,
  agentId: string,
  o: Partial<ReferralCodeRecord> = {},
): ReferralCodeRecord => ({
  id: `code-${n}`,
  agentId,
  // NM + six characters from the code alphabet (no 0, 1, I, L, O).
  code: `NM7K2P9${'XYZ'[n % 3]}`,
  isPrimary: false,
  isActive: true,
  createdAt: at(n),
  ...o,
});

const token = (
  n: number,
  agentId: string,
  o: Partial<AgentRefreshTokenRecord> = {},
): AgentRefreshTokenRecord => ({
  id: `token-${n}`,
  agentId,
  tokenHash: `token-hash-${n}`,
  expiresAt: at(60 * 24),
  revokedAt: null,
  createdAt: at(n),
  ...o,
});

const conflict = (reason: AgentConflictError['reason']): unknown =>
  expect.objectContaining({ name: 'AgentConflictError', reason });

export function defineAgentRepositoryContract(
  suiteName: string,
  makeWorld: () => Promise<AgentContractWorld>,
): void {
  describe(`${suiteName}: agent repository contract`, () => {
    let w: AgentContractWorld;

    beforeEach(async () => {
      w = await makeWorld();
    });
    afterEach(async () => {
      await w.cleanup?.();
    });

    const seedAgent = (n = 1): Promise<AgentRecord> =>
      w.agents.create(newAgent(n));

    describe('AgentRepository', () => {
      it('creates an agent as PENDING_APPROVAL with nothing verified', async () => {
        const created = await w.agents.create(newAgent(1));
        expect(created).toEqual({
          ...newAgent(1),
          status: 'PENDING_APPROVAL',
          rejectionReason: null,
          approvedAt: null,
          panVerifiedAt: null,
          payoutDetailsSet: false,
        });
      });

      it('finds by id and by phone hash, and returns null for neither', async () => {
        await seedAgent(1);
        expect((await w.agents.findById('agent-1'))?.name).toBe('Agent 1');
        expect((await w.agents.findByPhoneHash('v1:hash-1'))?.id).toBe(
          'agent-1',
        );
        expect(await w.agents.findById('nobody')).toBeNull();
        expect(await w.agents.findByPhoneHash('v1:nobody')).toBeNull();
      });

      it('refuses a reused id and a reused phone hash as conflicts', async () => {
        await seedAgent(1);
        await expect(w.agents.create(newAgent(1))).rejects.toEqual(
          conflict('DUPLICATE_ID'),
        );
        await expect(
          w.agents.create({ ...newAgent(2), phoneHash: 'v1:hash-1' }),
        ).rejects.toEqual(conflict('DUPLICATE_PHONE_HASH'));
        expect(await w.agents.findById('agent-2')).toBeNull();
      });

      it('updates the given fields only, including setting a field back to null', async () => {
        await seedAgent(1);
        const updated = await w.agents.update('agent-1', {
          status: 'ACTIVE',
          approvedAt: at(5),
          panLast4: '234F',
          panSealed: 'v1:sealed',
          panVerifiedAt: at(6),
          payoutDetailsSet: true,
        });
        expect(updated).toMatchObject({
          name: 'Agent 1',
          status: 'ACTIVE',
          approvedAt: at(5),
          panLast4: '234F',
          panSealed: 'v1:sealed',
          panVerifiedAt: at(6),
          payoutDetailsSet: true,
        });
        const cleared = await w.agents.update('agent-1', {
          panVerifiedAt: null,
          panLast4: null,
          panSealed: null,
        });
        expect(cleared).toMatchObject({
          status: 'ACTIVE',
          panVerifiedAt: null,
          panLast4: null,
          panSealed: null,
        });
        expect((await w.agents.findById('agent-1'))?.status).toBe('ACTIVE');
      });

      it('stores a rejection with its reason', async () => {
        await seedAgent(1);
        const rejected = await w.agents.update('agent-1', {
          status: 'REJECTED',
          rejectionReason: 'PAN does not match',
        });
        expect(rejected).toMatchObject({
          status: 'REJECTED',
          rejectionReason: 'PAN does not match',
        });
      });

      it('listPage is newest first, ties by id descending, with filters and a cursor', async () => {
        await w.agents.create({
          ...newAgent(1),
          name: 'Ravi Kumar',
          createdAt: at(1),
        });
        await w.agents.create({
          ...newAgent(2),
          name: 'ravi Shankar',
          createdAt: at(5),
        });
        await w.agents.create({
          ...newAgent(3),
          name: 'Mala',
          createdAt: at(5),
        });
        await w.agents.update('agent-3', { status: 'ACTIVE' });
        const ids = async (
          filter: Parameters<AgentRepository['listPage']>[0],
          page: Parameters<AgentRepository['listPage']>[1] = { limit: 10 },
        ) => (await w.agents.listPage(filter, page)).map((a) => a.id);
        expect(await ids({})).toEqual(['agent-3', 'agent-2', 'agent-1']);
        expect(await ids({ status: 'ACTIVE' })).toEqual(['agent-3']);
        expect(await ids({ namePrefix: 'RAV' })).toEqual([
          'agent-2',
          'agent-1',
        ]);
        expect(await ids({ phoneHash: 'v1:hash-1' })).toEqual(['agent-1']);
        expect(await ids({ ids: ['agent-1', 'agent-3'] })).toEqual([
          'agent-3',
          'agent-1',
        ]);
        expect(await ids({}, { limit: 2 })).toEqual(['agent-3', 'agent-2']);
        expect(
          await ids({}, { limit: 10, after: { at: at(5), id: 'agent-3' } }),
        ).toEqual(['agent-2', 'agent-1']);
      });

      it('rejects an update of an unknown agent', async () => {
        await expect(w.agents.update('nobody', { name: 'x' })).rejects.toThrow(
          'Unknown agent nobody',
        );
      });
    });

    describe('ReferralCodeRepository', () => {
      it('creates, finds, lists (oldest first) and checks existence', async () => {
        await seedAgent(1);
        await w.codes.create(code(1, 'agent-1', { isPrimary: true }));
        await w.codes.create(code(2, 'agent-1'));
        expect(await w.codes.findByCode(code(1, 'agent-1').code)).toEqual(
          code(1, 'agent-1', { isPrimary: true }),
        );
        expect((await w.codes.listByAgent('agent-1')).map((c) => c.id)).toEqual(
          ['code-1', 'code-2'],
        );
        expect(await w.codes.codeExists(code(2, 'agent-1').code)).toBe(true);
        expect(await w.codes.codeExists('NM222222')).toBe(false);
        expect(await w.codes.findByCode('NM222222')).toBeNull();
        expect(await w.codes.listByAgent('nobody')).toEqual([]);
      });

      it('refuses a reused code, id, or second primary code as conflicts', async () => {
        await seedAgent(1);
        await seedAgent(2);
        await w.codes.create(code(1, 'agent-1', { isPrimary: true }));
        await expect(
          w.codes.create({ ...code(2, 'agent-2'), code: code(1, 'x').code }),
        ).rejects.toEqual(conflict('DUPLICATE_CODE'));
        await expect(
          w.codes.create({ ...code(1, 'agent-1'), code: 'NM7K2P9Z' }),
        ).rejects.toEqual(conflict('DUPLICATE_ID'));
        await expect(
          w.codes.create(code(3, 'agent-1', { isPrimary: true })),
        ).rejects.toEqual(conflict('DUPLICATE_PRIMARY_CODE'));
      });

      it('setPrimary demotes and promotes; two primaries are a conflict', async () => {
        await seedAgent(1);
        await w.codes.create(code(1, 'agent-1', { isPrimary: true }));
        await w.codes.create(code(2, 'agent-1'));
        await expect(w.codes.setPrimary('code-2', true)).rejects.toEqual(
          conflict('DUPLICATE_PRIMARY_CODE'),
        );
        expect((await w.codes.setPrimary('code-1', false)).isPrimary).toBe(
          false,
        );
        expect((await w.codes.setPrimary('code-2', true)).isPrimary).toBe(true);
        expect(
          (await w.codes.listByAgent('agent-1')).map((c) => c.isPrimary),
        ).toEqual([false, true]);
        await expect(w.codes.setPrimary('nope', true)).rejects.toThrow(
          'Unknown referral code nope',
        );
      });

      it('lets two different agents each have a primary code', async () => {
        await seedAgent(1);
        await seedAgent(2);
        await w.codes.create(code(1, 'agent-1', { isPrimary: true }));
        await expect(
          w.codes.create(code(2, 'agent-2', { isPrimary: true })),
        ).resolves.toMatchObject({ agentId: 'agent-2', isPrimary: true });
      });
    });

    describe('AgentRefreshTokenRepository', () => {
      it('creates and finds by hash', async () => {
        await seedAgent(1);
        await w.tokens.create(token(1, 'agent-1'));
        expect(await w.tokens.findByHash('token-hash-1')).toEqual(
          token(1, 'agent-1'),
        );
        expect(await w.tokens.findByHash('nope')).toBeNull();
        await expect(
          w.tokens.create(token(1, 'agent-1', { tokenHash: 'other' })),
        ).rejects.toEqual(conflict('DUPLICATE_ID'));
      });

      it('rotate revokes the current token and stores the next one', async () => {
        await seedAgent(1);
        await w.tokens.create(token(1, 'agent-1'));
        const next = await w.tokens.rotate(
          'token-1',
          token(2, 'agent-1'),
          at(10),
        );
        expect(next).toEqual(token(2, 'agent-1'));
        expect((await w.tokens.findByHash('token-hash-1'))?.revokedAt).toEqual(
          at(10),
        );
        expect(await w.tokens.findByHash('token-hash-2')).toEqual(next);
      });

      it('rotate of an already revoked token is ALREADY_REVOKED and stores nothing', async () => {
        await seedAgent(1);
        await w.tokens.create(token(1, 'agent-1'));
        await w.tokens.rotate('token-1', token(2, 'agent-1'), at(10));
        await expect(
          w.tokens.rotate('token-1', token(3, 'agent-1'), at(11)),
        ).rejects.toEqual(conflict('ALREADY_REVOKED'));
        expect(await w.tokens.findByHash('token-hash-3')).toBeNull();
        // The first revocation time is kept.
        expect((await w.tokens.findByHash('token-hash-1'))?.revokedAt).toEqual(
          at(10),
        );
      });

      it('rotate of an unknown token fails without storing the next one', async () => {
        await seedAgent(1);
        await expect(
          w.tokens.rotate('nope', token(2, 'agent-1'), at(10)),
        ).rejects.toThrow('Unknown token nope');
        expect(await w.tokens.findByHash('token-hash-2')).toBeNull();
      });

      it('a failed insert in rotate leaves the current token usable', async () => {
        await seedAgent(1);
        await w.tokens.create(token(1, 'agent-1'));
        await w.tokens.create(token(2, 'agent-1'));
        // The next token reuses an existing id, so the insert half fails.
        await expect(
          w.tokens.rotate(
            'token-1',
            token(2, 'agent-1', { tokenHash: 'fresh' }),
            at(10),
          ),
        ).rejects.toEqual(conflict('DUPLICATE_ID'));
        expect(
          (await w.tokens.findByHash('token-hash-1'))?.revokedAt,
        ).toBeNull();
      });

      it('two parallel rotations of one token: exactly one wins', async () => {
        await seedAgent(1);
        await w.tokens.create(token(1, 'agent-1'));
        const results = await Promise.allSettled([
          w.tokens.rotate('token-1', token(2, 'agent-1'), at(10)),
          w.tokens.rotate('token-1', token(3, 'agent-1'), at(10)),
        ]);
        const won = results.filter((r) => r.status === 'fulfilled');
        const lost = results.filter((r) => r.status === 'rejected');
        expect(won).toHaveLength(1);
        expect(lost).toHaveLength(1);
        expect(lost[0].reason).toEqual(conflict('ALREADY_REVOKED'));
        // Exactly one next token exists.
        const stored = [
          await w.tokens.findByHash('token-hash-2'),
          await w.tokens.findByHash('token-hash-3'),
        ].filter((t) => t !== null);
        expect(stored).toHaveLength(1);
      });

      it('revoke reports whether the token was active', async () => {
        await seedAgent(1);
        await w.tokens.create(token(1, 'agent-1'));
        expect(await w.tokens.revoke('token-1', at(5))).toBe(true);
        expect(await w.tokens.revoke('token-1', at(6))).toBe(false);
        expect(await w.tokens.revoke('nope', at(6))).toBe(false);
        expect((await w.tokens.findByHash('token-hash-1'))?.revokedAt).toEqual(
          at(5),
        );
      });

      it("revokeAllForAgent revokes only that agent's still-active tokens", async () => {
        await seedAgent(1);
        await seedAgent(2);
        await w.tokens.create(token(1, 'agent-1'));
        await w.tokens.create(token(2, 'agent-1'));
        await w.tokens.create(token(3, 'agent-1', { revokedAt: at(1) }));
        await w.tokens.create(token(4, 'agent-2'));
        expect(await w.tokens.revokeAllForAgent('agent-1', at(9))).toBe(2);
        expect((await w.tokens.findByHash('token-hash-3'))?.revokedAt).toEqual(
          at(1),
        );
        expect(
          (await w.tokens.findByHash('token-hash-4'))?.revokedAt,
        ).toBeNull();
        expect(await w.tokens.revokeAllForAgent('agent-1', at(10))).toBe(0);
      });
    });

    describe('AgentPayoutDetailsRepository', () => {
      const details = (o: object = {}) => ({
        agentId: 'agent-1',
        method: 'UPI' as const,
        detailsSealed: 'v1:sealed-details',
        display: 'r***@okbank',
        verifiedAt: null,
        changedAt: at(3),
        ...o,
      });

      it('returns null before anything is saved', async () => {
        await seedAgent(1);
        expect(await w.payout.find('agent-1')).toBeNull();
      });

      it('saves, finds, and replaces (one row per agent)', async () => {
        await seedAgent(1);
        await w.payout.save(details());
        expect(await w.payout.find('agent-1')).toEqual(details());
        const replaced = details({
          method: 'BANK',
          detailsSealed: 'v1:other',
          display: 'HDFC ****1234',
          verifiedAt: at(7),
          changedAt: at(8),
        });
        await w.payout.save(replaced);
        expect(await w.payout.find('agent-1')).toEqual(replaced);
      });
    });

    describe('AgentUnitOfWork', () => {
      it('returns what the callback returns and commits its writes', async () => {
        const result = await w.uow.run(async (tx) => {
          await w.agents.create(newAgent(1), tx);
          await w.audit.record(
            {
              actorId: 'admin-1',
              action: 'agent.approve',
              entity: 'agent',
              entityId: 'agent-1',
            },
            tx,
          );
          return 'done';
        });
        expect(result).toBe('done');
        expect(await w.agents.findById('agent-1')).not.toBeNull();
        expect(await w.auditCount()).toBe(1);
      });

      it('rolls back every write made with the tx, the audit row included, when the callback throws', async () => {
        const boom = new Error('boom');
        await seedAgent(1);
        await expect(
          w.uow.run(async (tx) => {
            await w.agents.create(newAgent(2), tx);
            await w.agents.update('agent-1', { status: 'ACTIVE' }, tx);
            await w.codes.create(code(1, 'agent-2'), tx);
            await w.tokens.create(token(1, 'agent-2'), tx);
            await w.payout.save(
              {
                agentId: 'agent-2',
                method: 'UPI',
                detailsSealed: 's',
                display: 'd',
                verifiedAt: null,
                changedAt: at(1),
              },
              tx,
            );
            await w.audit.record(
              {
                actorId: 'admin-1',
                action: 'agent.approve',
                entity: 'agent',
                entityId: 'agent-1',
              },
              tx,
            );
            throw boom;
          }),
        ).rejects.toBe(boom);
        expect(await w.agents.findById('agent-2')).toBeNull();
        expect((await w.agents.findById('agent-1'))?.status).toBe(
          'PENDING_APPROVAL',
        );
        expect(await w.codes.listByAgent('agent-2')).toEqual([]);
        expect(await w.tokens.findByHash('token-hash-1')).toBeNull();
        expect(await w.payout.find('agent-2')).toBeNull();
        expect(await w.auditCount()).toBe(0);
      });

      it('rolls back the earlier writes when a later one hits a unique conflict', async () => {
        await seedAgent(1);
        await expect(
          w.uow.run(async (tx) => {
            await w.agents.create(newAgent(2), tx);
            await w.audit.record(
              {
                actorId: null,
                action: 'agent.apply',
                entity: 'agent',
                entityId: 'agent-2',
              },
              tx,
            );
            await w.agents.create(
              { ...newAgent(3), phoneHash: 'v1:hash-1' },
              tx,
            );
          }),
        ).rejects.toEqual(conflict('DUPLICATE_PHONE_HASH'));
        expect(await w.agents.findById('agent-2')).toBeNull();
        expect(await w.auditCount()).toBe(0);
      });

      it('keeps a write that was not given the tx', async () => {
        await expect(
          w.uow.run(async (tx) => {
            await w.agents.create(newAgent(1)); // no tx: outside the transaction
            await w.agents.create(newAgent(2), tx);
            throw new Error('boom');
          }),
        ).rejects.toThrow('boom');
        expect(await w.agents.findById('agent-1')).not.toBeNull();
        expect(await w.agents.findById('agent-2')).toBeNull();
      });

      it('refuses a nested run', async () => {
        await expect(
          w.uow.run(() => w.uow.run(() => Promise.resolve(1))),
        ).rejects.toThrow('Nested AgentUnitOfWork.run is not supported.');
      });
    });
  });
}
