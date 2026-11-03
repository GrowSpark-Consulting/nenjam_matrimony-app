/**
 * One behaviour suite for the client draft repository and the consent-code
 * store, run against BOTH the in-memory fakes (`pnpm test`) and the Prisma
 * adapters (database-gated, `pnpm test:agent-db`). If the two disagree, a
 * service tested on the fakes may not behave the same on the real database.
 *
 * What only the database can show (its CHECKs and trigger refusing a bad
 * write, two transactions racing) is tested in the Prisma-only specs.
 */
import type { AgentStatus } from '../agent/agent-status';
import { AgentConflictError } from '../ports/agent-data-ports';
import type {
  AgentClientConsentCodeStore,
  AgentClientDraftRepository,
  NewAgentClientDraft,
} from '../ports/agent-client-ports';
import type { AgentUnitOfWork } from '../ports/agent-unit-of-work.port';

export interface AgentClientContractWorld {
  uow: AgentUnitOfWork;
  drafts: AgentClientDraftRepository;
  codes: AgentClientConsentCodeStore;
  /** The rows the foreign keys need (the fakes keep only the agent's status). */
  seedAgent(id: string, status?: AgentStatus): Promise<void>;
  setAgentStatus(id: string, status: AgentStatus): Promise<void>;
  seedMember(id: string): Promise<void>;
  seedAttribution(id: string, agentId: string, memberId: string): Promise<void>;
  cleanup?(): Promise<void>;
}

/** Whole milliseconds: the database column keeps milliseconds. */
const T0 = new Date('2026-11-03T09:00:00.000Z');
const at = (minutes: number) => new Date(T0.getTime() + minutes * 60_000);
const DAY_MIN = 24 * 60;

const draft = (
  n: number,
  agentId: string,
  o: Partial<NewAgentClientDraft> = {},
): NewAgentClientDraft => ({
  id: `draft-${n}`,
  agentId,
  phoneHash: `v1:client-${n}`,
  phoneSealed: `sealed-phone-${n}`,
  phoneMasked: '+91 90***001',
  displayName: 'Priya S.',
  detailsSealed: `sealed-details-${n}`,
  expiresAt: at(14 * DAY_MIN),
  createdAt: at(n),
  ...o,
});

export function defineAgentClientContract(
  name: string,
  makeWorld: () => Promise<AgentClientContractWorld>,
): void {
  describe(`agent client drafts contract (${name})`, () => {
    let w: AgentClientContractWorld;

    beforeEach(async () => {
      w = await makeWorld();
      await w.seedAgent('agent-1');
      await w.seedAgent('agent-2');
    });

    afterEach(async () => {
      await w.cleanup?.();
    });

    const submitted = async (n: number, agentId = 'agent-1', o = {}) => {
      await w.drafts.create(draft(n, agentId, o));
      const row = await w.drafts.submit(
        `draft-${n}`,
        agentId,
        { submittedAt: at(n + 1), expiresAt: at(n + 1 + 14 * DAY_MIN) },
        at(n + 1),
      );
      if (row === null) throw new Error('submit failed in set-up');
      return row;
    };

    describe('create and read', () => {
      it('stores a DRAFT with nothing submitted, accepted or closed', async () => {
        const row = await w.drafts.create(draft(1, 'agent-1'));
        expect(row).toEqual({
          ...draft(1, 'agent-1'),
          status: 'DRAFT',
          submittedAt: null,
          acceptedAt: null,
          closedAt: null,
          closedReason: null,
          memberId: null,
          attributionId: null,
        });
        expect(await w.drafts.findByIdForAgent('draft-1', 'agent-1')).toEqual(
          row,
        );
      });

      it("another agent's draft looks exactly like a missing one", async () => {
        await w.drafts.create(draft(1, 'agent-1'));
        expect(
          await w.drafts.findByIdForAgent('draft-1', 'agent-2'),
        ).toBeNull();
        expect(await w.drafts.findByIdForAgent('nope', 'agent-1')).toBeNull();
      });

      it('one open draft per agent and phone; another agent may add the same phone', async () => {
        await w.drafts.create(draft(1, 'agent-1'));
        await expect(
          w.drafts.create(draft(2, 'agent-1', { phoneHash: 'v1:client-1' })),
        ).rejects.toEqual(
          new AgentConflictError('DUPLICATE_OPEN_CLIENT_DRAFT'),
        );
        await expect(
          w.drafts.create(draft(3, 'agent-2', { phoneHash: 'v1:client-1' })),
        ).resolves.toMatchObject({ id: 'draft-3' });
      });

      it('a waiting draft also holds the slot; a closed one does not', async () => {
        await submitted(1);
        await expect(
          w.drafts.create(draft(2, 'agent-1', { phoneHash: 'v1:client-1' })),
        ).rejects.toEqual(
          new AgentConflictError('DUPLICATE_OPEN_CLIENT_DRAFT'),
        );
        expect(await w.drafts.close('draft-1', 'TIMED_OUT', at(5))).toBe(true);
        await expect(
          w.drafts.create(draft(2, 'agent-1', { phoneHash: 'v1:client-1' })),
        ).resolves.toMatchObject({ status: 'DRAFT' });
      });

      it('refuses a reused id', async () => {
        await w.drafts.create(draft(1, 'agent-1'));
        await expect(
          w.drafts.create(draft(1, 'agent-2', { phoneHash: 'v1:other' })),
        ).rejects.toEqual(new AgentConflictError('DUPLICATE_ID'));
      });

      it('a create inside a failed transaction leaves nothing', async () => {
        await expect(
          w.uow.run(async (tx) => {
            await w.drafts.create(draft(1, 'agent-1'), tx);
            throw new Error('boom');
          }),
        ).rejects.toThrow('boom');
        expect(
          await w.drafts.findByIdForAgent('draft-1', 'agent-1'),
        ).toBeNull();
      });
    });

    describe('the agent list', () => {
      it('is newest first, own drafts only, and pages strictly after the cursor (ties by id)', async () => {
        await w.drafts.create(draft(1, 'agent-1'));
        await w.drafts.create(draft(2, 'agent-1', { createdAt: at(5) }));
        await w.drafts.create(draft(3, 'agent-1', { createdAt: at(5) }));
        await w.drafts.create(draft(4, 'agent-2'));
        const now = at(10);
        const first = await w.drafts.listPageByAgent(
          'agent-1',
          { now },
          { limit: 2 },
        );
        expect(first.map((r) => r.id)).toEqual(['draft-3', 'draft-2']);
        const rest = await w.drafts.listPageByAgent(
          'agent-1',
          { now },
          { limit: 2, after: { at: at(5), id: 'draft-2' } },
        );
        expect(rest.map((r) => r.id)).toEqual(['draft-1']);
      });

      it('filters by the status the agent sees: an overdue open draft is EXPIRED', async () => {
        await w.drafts.create(draft(1, 'agent-1', { expiresAt: at(100) }));
        await w.drafts.create(draft(2, 'agent-1'));
        await submitted(3);
        await w.drafts.create(draft(4, 'agent-1'));
        await w.drafts.close('draft-4', 'TIMED_OUT', at(20));
        const ids = async (
          status: 'DRAFT' | 'WAITING_FOR_CLIENT' | 'EXPIRED',
        ) =>
          (
            await w.drafts.listPageByAgent(
              'agent-1',
              { status, now: at(100) },
              { limit: 10 },
            )
          ).map((r) => r.id);
        expect(await ids('DRAFT')).toEqual(['draft-2']);
        expect(await ids('WAITING_FOR_CLIENT')).toEqual(['draft-3']);
        expect(await ids('EXPIRED')).toEqual(['draft-4', 'draft-1']);
      });

      it('counts open drafts (overdue ones too, until they are closed)', async () => {
        await w.drafts.create(draft(1, 'agent-1', { expiresAt: at(10) }));
        await submitted(2);
        await w.drafts.create(draft(3, 'agent-1'));
        await w.drafts.close('draft-3', 'TIMED_OUT', at(5));
        await w.drafts.create(draft(4, 'agent-2'));
        expect(await w.drafts.countOpen('agent-1')).toBe(2);
      });
    });

    describe('changes while DRAFT', () => {
      it('replaces the details only while the DRAFT is open and the agent owns it', async () => {
        await w.drafts.create(draft(1, 'agent-1', { expiresAt: at(60) }));
        const change = { displayName: 'Meena R.', detailsSealed: 'sealed-new' };
        expect(
          await w.drafts.updateDetails('draft-1', 'agent-2', change, at(10)),
        ).toBeNull();
        expect(
          await w.drafts.updateDetails('draft-1', 'agent-1', change, at(60)),
        ).toBeNull();
        expect(
          await w.drafts.updateDetails('draft-1', 'agent-1', change, at(10)),
        ).toMatchObject({ ...change, status: 'DRAFT' });
      });

      it('submit moves DRAFT to WAITING_FOR_CLIENT once, with the new expiry', async () => {
        await w.drafts.create(draft(1, 'agent-1'));
        const row = await w.drafts.submit(
          'draft-1',
          'agent-1',
          { submittedAt: at(30), expiresAt: at(30 + DAY_MIN) },
          at(30),
        );
        expect(row).toMatchObject({
          status: 'WAITING_FOR_CLIENT',
          submittedAt: at(30),
          expiresAt: at(30 + DAY_MIN),
        });
        expect(
          await w.drafts.submit(
            'draft-1',
            'agent-1',
            { submittedAt: at(31), expiresAt: at(31 + DAY_MIN) },
            at(31),
          ),
        ).toBeNull();
        expect(
          await w.drafts.updateDetails(
            'draft-1',
            'agent-1',
            { displayName: 'X Y.', detailsSealed: 'z' },
            at(32),
          ),
        ).toBeNull();
      });

      it('an overdue DRAFT cannot be submitted', async () => {
        await w.drafts.create(draft(1, 'agent-1', { expiresAt: at(10) }));
        expect(
          await w.drafts.submit(
            'draft-1',
            'agent-1',
            { submittedAt: at(10), expiresAt: at(10 + DAY_MIN) },
            at(10),
          ),
        ).toBeNull();
      });

      it("discards only the agent's own DRAFT", async () => {
        await w.drafts.create(draft(1, 'agent-1'));
        await submitted(2);
        expect(await w.drafts.discard('draft-1', 'agent-2')).toBe(false);
        expect(await w.drafts.discard('draft-2', 'agent-1')).toBe(false);
        expect(await w.drafts.discard('draft-1', 'agent-1')).toBe(true);
        expect(
          await w.drafts.findByIdForAgent('draft-1', 'agent-1'),
        ).toBeNull();
        expect(await w.drafts.discard('draft-1', 'agent-1')).toBe(false);
      });
    });

    describe('lookups by phone hash (every pepper version)', () => {
      it("finds the agent's open draft under any of the hashes", async () => {
        await w.drafts.create(draft(1, 'agent-1', { phoneHash: 'v0:old' }));
        expect(
          await w.drafts.findOpenByAgentAndHashes('agent-1', [
            'v1:new',
            'v0:old',
          ]),
        ).toMatchObject({ id: 'draft-1' });
        expect(
          await w.drafts.findOpenByAgentAndHashes('agent-2', [
            'v1:new',
            'v0:old',
          ]),
        ).toBeNull();
        await w.drafts.close('draft-1', 'TIMED_OUT', at(5));
        expect(
          await w.drafts.findOpenByAgentAndHashes('agent-1', ['v0:old']),
        ).toBeNull();
      });

      it('knows when this client rejected this agent, under any hash', async () => {
        await submitted(1, 'agent-1', { phoneHash: 'v0:old' });
        expect(
          await w.drafts.wasRejectedBy('agent-1', ['v1:new', 'v0:old']),
        ).toBe(false);
        await w.drafts.markRejected('draft-1', ['v1:new', 'v0:old'], at(10));
        expect(
          await w.drafts.wasRejectedBy('agent-1', ['v1:new', 'v0:old']),
        ).toBe(true);
        expect(await w.drafts.wasRejectedBy('agent-2', ['v0:old'])).toBe(false);
        expect(await w.drafts.wasRejectedBy('agent-1', ['v1:new'])).toBe(false);
      });

      it('finds a draft by id only for its own phone, in any status', async () => {
        await submitted(1);
        expect(
          await w.drafts.findForPhone('draft-1', ['v1:client-1']),
        ).toMatchObject({
          status: 'WAITING_FOR_CLIENT',
        });
        expect(
          await w.drafts.findForPhone('draft-1', ['v1:client-2']),
        ).toBeNull();
      });

      it("lists the phone's waiting drafts that have not run out, oldest first, any agent", async () => {
        const phone = { phoneHash: 'v1:shared' };
        await submitted(1, 'agent-2', phone);
        await submitted(2, 'agent-1', phone);
        await w.drafts.create(draft(3, 'agent-1', { phoneHash: 'v1:other' }));
        await submitted(4, 'agent-1', { phoneHash: 'v1:mine' });
        const waiting = await w.drafts.listWaitingForHashes(
          ['v1:shared', 'v1:mine'],
          at(10),
        );
        expect(waiting.map((r) => r.id)).toEqual([
          'draft-1',
          'draft-2',
          'draft-4',
        ]);
        const later = await w.drafts.listWaitingForHashes(
          ['v1:shared'],
          at(2 + 1 + 14 * DAY_MIN),
        );
        // draft-1's time ran out at minute 2 + 14 days; draft-2's one minute later.
        expect(later.map((r) => r.id)).toEqual([]);
      });
    });

    describe('the client answers', () => {
      it('accept: locks only a waiting, unexpired draft for the phone, then records the member and attribution and deletes the PII', async () => {
        await submitted(1);
        await w.seedMember('member-1');
        await w.seedAttribution('attribution-1', 'agent-1', 'member-1');
        const accepted = await w.uow.run(async (tx) => {
          expect(
            await w.drafts.lockWaitingForAccept(
              'draft-1',
              ['v1:client-2'],
              at(10),
              tx,
            ),
          ).toBeNull();
          expect(
            await w.drafts.lockWaitingForAccept(
              'draft-1',
              ['v1:client-1'],
              at(2 + 14 * DAY_MIN),
              tx,
            ),
          ).toBeNull();
          const locked = await w.drafts.lockWaitingForAccept(
            'draft-1',
            ['v1:client-1'],
            at(10),
            tx,
          );
          expect(locked).toMatchObject({ id: 'draft-1' });
          return w.drafts.markAccepted(
            'draft-1',
            {
              memberId: 'member-1',
              attributionId: 'attribution-1',
              acceptedAt: at(10),
            },
            tx,
          );
        });
        expect(accepted).toMatchObject({
          status: 'ACCEPTED',
          memberId: 'member-1',
          attributionId: 'attribution-1',
          acceptedAt: at(10),
          phoneSealed: null,
          detailsSealed: null,
          closedAt: null,
        });
        await w.uow.run(async (tx) => {
          expect(
            await w.drafts.lockWaitingForAccept(
              'draft-1',
              ['v1:client-1'],
              at(11),
              tx,
            ),
          ).toBeNull();
        });
      });

      it('reject: keeps the sealed phone, deletes the details, and only once', async () => {
        await submitted(1);
        const rejected = await w.drafts.markRejected(
          'draft-1',
          ['v1:client-1'],
          at(10),
        );
        expect(rejected).toMatchObject({
          status: 'REJECTED',
          closedAt: at(10),
          phoneSealed: 'sealed-phone-1',
          detailsSealed: null,
        });
        expect(
          await w.drafts.markRejected('draft-1', ['v1:client-1'], at(11)),
        ).toBeNull();
      });

      it('reject refuses another phone, a DRAFT and an overdue invitation', async () => {
        await submitted(1);
        await w.drafts.create(draft(2, 'agent-1'));
        expect(
          await w.drafts.markRejected('draft-1', ['v1:client-2'], at(10)),
        ).toBeNull();
        expect(
          await w.drafts.markRejected('draft-2', ['v1:client-2'], at(10)),
        ).toBeNull();
        expect(
          await w.drafts.markRejected(
            'draft-1',
            ['v1:client-1'],
            at(2 + 14 * DAY_MIN),
          ),
        ).toBeNull();
      });
    });

    describe('closing', () => {
      it('close: an open draft becomes EXPIRED with its reason and loses its PII; a closed one stays', async () => {
        await submitted(1);
        expect(
          await w.drafts.close('draft-1', 'CLIENT_ALREADY_MEMBER', at(10)),
        ).toBe(true);
        expect(
          await w.drafts.findByIdForAgent('draft-1', 'agent-1'),
        ).toMatchObject({
          status: 'EXPIRED',
          closedAt: at(10),
          closedReason: 'CLIENT_ALREADY_MEMBER',
          phoneSealed: null,
          detailsSealed: null,
        });
        expect(await w.drafts.close('draft-1', 'TIMED_OUT', at(11))).toBe(
          false,
        );
      });

      it("closes every other open draft for the phone, any agent's, and says which", async () => {
        const phone = { phoneHash: 'v1:shared' };
        await submitted(1, 'agent-1', phone);
        await submitted(2, 'agent-2', phone);
        await w.seedAgent('agent-3');
        await w.drafts.create(draft(3, 'agent-3', phone));
        await w.drafts.create(draft(4, 'agent-2', { phoneHash: 'v1:other' }));
        const closed = await w.drafts.closeOthersForPhone(
          ['v1:shared'],
          'draft-1',
          'CLIENT_ACCEPTED_ANOTHER',
          at(10),
        );
        expect([...closed].sort()).toEqual(['draft-2', 'draft-3']);
        expect(
          (await w.drafts.findByIdForAgent('draft-2', 'agent-2'))?.closedReason,
        ).toBe('CLIENT_ACCEPTED_ANOTHER');
        expect(
          (await w.drafts.findByIdForAgent('draft-1', 'agent-1'))?.status,
        ).toBe('WAITING_FOR_CLIENT');
        expect(
          (await w.drafts.findByIdForAgent('draft-4', 'agent-2'))?.status,
        ).toBe('DRAFT');
      });

      it('expires due drafts, oldest expiry first, in batches; per agent or for all', async () => {
        await w.drafts.create(draft(1, 'agent-1', { expiresAt: at(30) }));
        await w.drafts.create(draft(2, 'agent-1', { expiresAt: at(20) }));
        await w.drafts.create(draft(3, 'agent-2', { expiresAt: at(25) }));
        await w.drafts.create(draft(4, 'agent-1', { expiresAt: at(90) }));
        expect(await w.drafts.expireDue('agent-2', at(40), 10)).toEqual([
          'draft-3',
        ]);
        await w.drafts.create(draft(5, 'agent-2', { expiresAt: at(35) }));
        expect(await w.drafts.expireDue(null, at(40), 2)).toEqual([
          'draft-2',
          'draft-1',
        ]);
        expect(await w.drafts.expireDue(null, at(40), 2)).toEqual(['draft-5']);
        expect(await w.drafts.expireDue(null, at(40), 2)).toEqual([]);
        expect(
          await w.drafts.findByIdForAgent('draft-1', 'agent-1'),
        ).toMatchObject({
          status: 'EXPIRED',
          closedReason: 'TIMED_OUT',
          detailsSealed: null,
          phoneSealed: null,
        });
        expect(
          (await w.drafts.findByIdForAgent('draft-4', 'agent-1'))?.status,
        ).toBe('DRAFT');
      });

      it('closes the open drafts of a TERMINATED agent, and only those', async () => {
        await w.drafts.create(draft(1, 'agent-1'));
        await submitted(2, 'agent-1');
        await w.drafts.create(draft(3, 'agent-2'));
        await w.setAgentStatus('agent-1', 'TERMINATED');
        expect(
          [...(await w.drafts.closeOfTerminatedAgents(at(10), 10))].sort(),
        ).toEqual(['draft-1', 'draft-2']);
        expect(
          (await w.drafts.findByIdForAgent('draft-2', 'agent-1'))?.closedReason,
        ).toBe('AGENT_TERMINATED');
        expect(await w.drafts.closeOfTerminatedAgents(at(10), 10)).toEqual([]);
        expect(
          (await w.drafts.findByIdForAgent('draft-3', 'agent-2'))?.status,
        ).toBe('DRAFT');
      });
    });

    describe('consent codes', () => {
      const code = (hash: string, challengeId: string, expiresAt = at(5)) => ({
        phoneHash: hash,
        challengeId,
        expiresAt,
      });

      it('keeps one pointer per phone hash, the newest', async () => {
        await w.codes.save(code('v1:a', 'challenge-1'));
        await w.codes.save(code('v1:a', 'challenge-2', at(6)));
        expect(await w.codes.find(['v1:a'])).toEqual(
          code('v1:a', 'challenge-2', at(6)),
        );
      });

      it('finds under the first hash that has one, and deletes by hashes', async () => {
        await w.codes.save(code('v0:old', 'challenge-old'));
        expect(await w.codes.find(['v1:new', 'v0:old'])).toMatchObject({
          challengeId: 'challenge-old',
        });
        await w.codes.delete(['v1:new', 'v0:old']);
        expect(await w.codes.find(['v1:new', 'v0:old'])).toBeNull();
      });

      it('purges pointers expired before a moment, at most `limit` at a time', async () => {
        await w.codes.save(code('v1:a', 'c-a', at(1)));
        await w.codes.save(code('v1:b', 'c-b', at(2)));
        await w.codes.save(code('v1:c', 'c-c', at(9)));
        expect(await w.codes.purgeExpired(at(5), 1)).toBe(1);
        expect(await w.codes.purgeExpired(at(5), 10)).toBe(1);
        expect(await w.codes.purgeExpired(at(5), 10)).toBe(0);
        expect(await w.codes.find(['v1:c'])).toMatchObject({
          challengeId: 'c-c',
        });
      });
    });
  });
}
