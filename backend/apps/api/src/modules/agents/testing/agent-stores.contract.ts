/**
 * Behaviour suite for the attribution repository, the applicant store and the
 * code-attempt store, run against BOTH the in-memory fakes (default
 * `pnpm test`) and the Prisma adapters (database-gated, `pnpm test:agent-db`).
 * See `agent-repositories.contract.ts` for the rest of the repositories.
 *
 * The opportunistic purge exists only in the real adapters, so it is tested
 * in the Prisma-only spec, not here.
 */
import {
  AgentConflictError,
  type AgentApplicantRepository,
  type AgentRepository,
  type ReferralAttributionRecord,
  type ReferralAttributionRepository,
  type ReferralCodeAttemptStore,
  type ReferralCodeRepository,
} from '../ports/agent-data-ports';

export interface AgentStoresWorld {
  agents: AgentRepository;
  codes: ReferralCodeRepository;
  attributions: ReferralAttributionRepository;
  applicants: AgentApplicantRepository;
  attempts: ReferralCodeAttemptStore;
  /** Makes a member id usable in an attribution (the real database needs a user row). */
  seedMember(memberId: string): Promise<void>;
  cleanup?(): Promise<void>;
}

const T0 = new Date('2026-10-29T09:00:00.000Z');
const at = (minutes: number) => new Date(T0.getTime() + minutes * 60_000);

const conflict = (reason: AgentConflictError['reason']): unknown =>
  expect.objectContaining({ name: 'AgentConflictError', reason });

export function defineAgentStoresContract(
  suiteName: string,
  makeWorld: () => Promise<AgentStoresWorld>,
): void {
  describe(`${suiteName}: attribution, applicant and attempt stores contract`, () => {
    let w: AgentStoresWorld;

    beforeEach(async () => {
      w = await makeWorld();
      for (const n of [1, 2]) {
        await w.agents.create({
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
      }
      await w.codes.create({
        id: 'code-1',
        agentId: 'agent-1',
        code: 'NM7K2P9X',
        isPrimary: true,
        isActive: true,
        createdAt: at(0),
      });
    });
    afterEach(async () => {
      await w.cleanup?.();
    });

    describe('ReferralAttributionRepository', () => {
      const attribution = async (
        n: number,
        o: Partial<ReferralAttributionRecord> = {},
      ): Promise<ReferralAttributionRecord> => {
        const memberId = o.memberId === undefined ? `member-${n}` : o.memberId;
        if (memberId !== null) await w.seedMember(memberId);
        return {
          id: `attr-${String(n).padStart(2, '0')}`,
          memberId,
          agentId: 'agent-1',
          codeId: 'code-1',
          source: 'CODE_AT_SIGNUP',
          memberPhoneHash: `v1:member-hash-${n}`,
          attributedAt: at(n),
          status: 'ACTIVE',
          windowEndsAt: at(60 * 24 * 60),
          needsReview: false,
          ...o,
        };
      };
      const add = async (
        n: number,
        o: Partial<ReferralAttributionRecord> = {},
      ) => w.attributions.create(await attribution(n, o));

      it('creates and finds by member id', async () => {
        const created = await add(1);
        expect(created).toEqual(await attribution(1));
        expect(await w.attributions.findByMemberId('member-1')).toEqual(
          created,
        );
        expect(await w.attributions.findByMemberId('nobody')).toBeNull();
      });

      it('keeps every field, including a review flag and the extra sources', async () => {
        await add(1, { needsReview: true, status: 'REJECTED' });
        await add(2, { source: 'ADDED_BY_AGENT', status: 'CONVERTED' });
        await add(3, { source: 'ADMIN_SET' });
        expect(await w.attributions.findByMemberId('member-1')).toMatchObject({
          needsReview: true,
          status: 'REJECTED',
        });
        expect(await w.attributions.findByMemberId('member-2')).toMatchObject({
          source: 'ADDED_BY_AGENT',
          status: 'CONVERTED',
        });
        expect(await w.attributions.findByMemberId('member-3')).toMatchObject({
          source: 'ADMIN_SET',
        });
      });

      it('refuses a second attribution for the same member, phone hash or id', async () => {
        await add(1);
        await expect(
          w.attributions.create(await attribution(2, { memberId: 'member-1' })),
        ).rejects.toEqual(conflict('DUPLICATE_ATTRIBUTION'));
        await expect(
          add(3, { memberPhoneHash: 'v1:member-hash-1' }),
        ).rejects.toEqual(conflict('DUPLICATE_ATTRIBUTION'));
        await expect(add(4, { id: 'attr-01' })).rejects.toEqual(
          conflict('DUPLICATE_ATTRIBUTION'),
        );
      });

      it('needs a member phone hash', async () => {
        await expect(add(1, { memberPhoneHash: '' })).rejects.toThrow(
          RangeError,
        );
      });

      it('allows several attributions whose member and code are gone (null)', async () => {
        await add(1, { memberId: null, codeId: null });
        await add(2, { memberId: null, codeId: null });
        const rows = await w.attributions.listByAgent('agent-1');
        expect(rows).toHaveLength(2);
        expect(
          rows.every((r) => r.memberId === null && r.codeId === null),
        ).toBe(true);
      });

      it("OWN-AGENT SCOPING: findByIdForAgent hides another agent's row", async () => {
        await add(1, { agentId: 'agent-1' });
        await add(2, { agentId: 'agent-2', codeId: null });
        expect(
          (await w.attributions.findByIdForAgent('attr-01', 'agent-1'))?.id,
        ).toBe('attr-01');
        // Another agent's row looks exactly like a missing one.
        expect(
          await w.attributions.findByIdForAgent('attr-02', 'agent-1'),
        ).toBeNull();
        expect(
          await w.attributions.findByIdForAgent('attr-99', 'agent-1'),
        ).toBeNull();
        expect(
          (await w.attributions.findByIdForAgent('attr-02', 'agent-2'))?.id,
        ).toBe('attr-02');
      });

      it('findByPhoneHash finds the attribution stored under that exact hash', async () => {
        await add(1);
        expect(
          (await w.attributions.findByPhoneHash('v1:member-hash-1'))?.id,
        ).toBe('attr-01');
        expect(
          await w.attributions.findByPhoneHash('v0:member-hash-1'),
        ).toBeNull();
        expect(await w.attributions.findByPhoneHash('nope')).toBeNull();
      });

      it("findById finds any agent's attribution; null when unknown", async () => {
        await add(1);
        expect((await w.attributions.findById('attr-01'))?.memberId).toBe(
          'member-1',
        );
        expect(await w.attributions.findById('nope')).toBeNull();
      });

      describe('correct (admin)', () => {
        it('changes only the given fields and only from the expected status', async () => {
          await add(1, { needsReview: true });
          const done = await w.attributions.correct('attr-01', 'ACTIVE', {
            agentId: 'agent-2',
            source: 'ADMIN_SET',
            needsReview: false,
          });
          expect(done).toMatchObject({
            agentId: 'agent-2',
            source: 'ADMIN_SET',
            needsReview: false,
            status: 'ACTIVE',
            memberId: 'member-1',
            windowEndsAt: at(60 * 24 * 60),
          });
          // Wrong expected status: nothing changes.
          expect(
            await w.attributions.correct('attr-01', 'REJECTED', {
              status: 'EXPIRED',
            }),
          ).toBeNull();
          expect((await w.attributions.findById('attr-01'))?.status).toBe(
            'ACTIVE',
          );
          expect(
            await w.attributions.correct('nope', 'ACTIVE', {
              needsReview: false,
            }),
          ).toBeNull();
        });

        it('rejects an attribution', async () => {
          await add(1);
          expect(
            (
              await w.attributions.correct('attr-01', 'ACTIVE', {
                status: 'REJECTED',
              })
            )?.status,
          ).toBe('REJECTED');
        });

        it('two parallel corrections of one attribution: exactly one wins', async () => {
          await add(1);
          const results = await Promise.all([
            w.attributions.correct('attr-01', 'ACTIVE', { status: 'REJECTED' }),
            w.attributions.correct('attr-01', 'ACTIVE', { status: 'EXPIRED' }),
          ]);
          expect(results.filter((r) => r !== null)).toHaveLength(1);
        });
      });

      it('reports whether a phone hash is already credited', async () => {
        await add(1);
        expect(
          await w.attributions.isPhoneHashCredited('v1:member-hash-1'),
        ).toBe(true);
        expect(await w.attributions.isPhoneHashCredited('v1:other')).toBe(
          false,
        );
      });

      it("lists only the agent's own rows", async () => {
        await add(1, { agentId: 'agent-1' });
        await add(2, { agentId: 'agent-2', codeId: null });
        await add(3, { agentId: 'agent-1' });
        expect(
          (await w.attributions.listByAgent('agent-1')).map((r) => r.id),
        ).toEqual(['attr-01', 'attr-03']);
        expect(await w.attributions.listByAgent('nobody')).toEqual([]);
      });

      describe('listPageByAgent', () => {
        const seedPages = async () => {
          await add(1);
          await add(2);
          await add(3);
          // Two rows share the newest timestamp: order falls back to id, descending.
          await add(4, { attributedAt: at(10) });
          await add(5, { attributedAt: at(10) });
          await add(6, {
            agentId: 'agent-2',
            codeId: null,
            attributedAt: at(11),
          });
        };

        it('is newest first, ties broken by id descending, own agent only', async () => {
          await seedPages();
          const page = await w.attributions.listPageByAgent('agent-1', {
            limit: 10,
          });
          expect(page.map((r) => r.id)).toEqual([
            'attr-05',
            'attr-04',
            'attr-03',
            'attr-02',
            'attr-01',
          ]);
        });

        it('pages with a cursor: strictly after, no row skipped or repeated', async () => {
          await seedPages();
          const seen: string[] = [];
          let after: { at: Date; id: string } | undefined;
          for (let i = 0; i < 5; i++) {
            const page = await w.attributions.listPageByAgent('agent-1', {
              limit: 2,
              after,
            });
            if (page.length === 0) break;
            seen.push(...page.map((r) => r.id));
            const last = page[page.length - 1];
            after = { at: last.attributedAt, id: last.id };
          }
          expect(seen).toEqual([
            'attr-05',
            'attr-04',
            'attr-03',
            'attr-02',
            'attr-01',
          ]);
        });

        it('a cursor in the middle of a timestamp tie returns only the rows after it', async () => {
          await seedPages();
          const page = await w.attributions.listPageByAgent('agent-1', {
            limit: 10,
            after: { at: at(10), id: 'attr-05' },
          });
          expect(page.map((r) => r.id)).toEqual([
            'attr-04',
            'attr-03',
            'attr-02',
            'attr-01',
          ]);
        });

        it('honours the limit and returns an empty page past the end', async () => {
          await seedPages();
          expect(
            await w.attributions.listPageByAgent('agent-1', { limit: 1 }),
          ).toHaveLength(1);
          expect(
            await w.attributions.listPageByAgent('agent-1', {
              limit: 5,
              after: { at: at(1), id: 'attr-01' },
            }),
          ).toEqual([]);
        });
      });
    });

    describe('AgentApplicantRepository', () => {
      const applicant = (o: object = {}) => ({
        phoneHash: 'v1:applicant-1',
        phoneSealed: 'v1:sealed-phone',
        expiresAt: at(30),
        ...o,
      });

      it('saves, finds and deletes', async () => {
        expect(await w.applicants.find('v1:applicant-1')).toBeNull();
        await w.applicants.save(applicant());
        expect(await w.applicants.find('v1:applicant-1')).toEqual(applicant());
        await w.applicants.delete('v1:applicant-1');
        expect(await w.applicants.find('v1:applicant-1')).toBeNull();
      });

      it('save replaces the record for the same phone hash', async () => {
        await w.applicants.save(applicant());
        await w.applicants.save(
          applicant({ phoneSealed: 'v1:newer', expiresAt: at(90) }),
        );
        expect(await w.applicants.find('v1:applicant-1')).toEqual(
          applicant({ phoneSealed: 'v1:newer', expiresAt: at(90) }),
        );
      });

      it('returns an expired record (the caller checks the expiry)', async () => {
        await w.applicants.save(applicant({ expiresAt: new Date(0) }));
        expect((await w.applicants.find('v1:applicant-1'))?.expiresAt).toEqual(
          new Date(0),
        );
      });

      it('deleting an unknown record is not an error', async () => {
        await expect(w.applicants.delete('v1:nobody')).resolves.toBeUndefined();
      });
    });

    describe('ReferralCodeAttemptStore', () => {
      const long = new Date(0);

      it('counts attempts per requester and per code, strictly after `since`', async () => {
        await w.attempts.record({
          requesterKey: 'req-a',
          codeKey: 'NM7K2P9X',
          at: at(1),
        });
        await w.attempts.record({
          requesterKey: 'req-a',
          codeKey: 'NM7K2P9Y',
          at: at(2),
        });
        await w.attempts.record({
          requesterKey: 'req-b',
          codeKey: 'NM7K2P9X',
          at: at(3),
        });
        expect(await w.attempts.window('REQUESTER', 'req-a', long)).toEqual({
          count: 2,
          oldestAt: at(1),
        });
        expect(await w.attempts.window('CODE', 'NM7K2P9X', long)).toEqual({
          count: 2,
          oldestAt: at(1),
        });
        // `since` is exclusive: the attempt exactly at `since` is not counted.
        expect(await w.attempts.window('REQUESTER', 'req-a', at(1))).toEqual({
          count: 1,
          oldestAt: at(2),
        });
      });

      it('reports nothing for a key never seen', async () => {
        expect(await w.attempts.window('REQUESTER', 'nobody', long)).toEqual({
          count: 0,
          oldestAt: null,
        });
      });

      it('stores an attempt with no well-formed code for the requester only', async () => {
        await w.attempts.record({
          requesterKey: 'req-a',
          codeKey: null,
          at: at(1),
        });
        expect(
          (await w.attempts.window('REQUESTER', 'req-a', long)).count,
        ).toBe(1);
      });

      it.each(['203.0.113.7', '2001:db8::1', 'requester:203.0.113.7'])(
        'refuses a raw IP as the requester key (%s) and stores nothing',
        async (key) => {
          await expect(
            w.attempts.record({ requesterKey: key, codeKey: null, at: at(1) }),
          ).rejects.toThrow(RangeError);
          expect((await w.attempts.window('REQUESTER', key, long)).count).toBe(
            0,
          );
        },
      );
    });
  });
}
