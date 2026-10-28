import type { AgentRepository } from '../ports/agent-data-ports';
import {
  AgentPermissionDeniedError,
  AgentPermissionPort,
} from '../ports/agent-platform-ports';
import type { AgentTx } from '../ports/agent-unit-of-work.port';
import { FakeAgentAudit, FakeAgentPermission } from './fake-agent-platform';
import {
  FakeAgentRefreshTokenRepository,
  FakeAgentRepository,
  FakeReferralAttributionRepository,
  FakeReferralCodeRepository,
} from './fake-agent-repositories';
import { FakeAgentUnitOfWork } from './fake-agent-unit-of-work';

const NOW = new Date('2026-10-28T10:00:00.000Z');
const LATER = new Date('2026-11-27T10:00:00.000Z');

const setup = () => ({
  uow: new FakeAgentUnitOfWork(),
  agents: new FakeAgentRepository(),
  codes: new FakeReferralCodeRepository(),
  tokens: new FakeAgentRefreshTokenRepository(),
  attributions: new FakeReferralAttributionRepository(),
  audit: new FakeAgentAudit(),
});

const newAgent = (id = 'agent-1', phoneHash = 'phone-hash-1') => ({
  id,
  phoneHash,
  phoneE164: '+919876543210',
  name: 'Ravi Kumar',
  city: 'Chennai',
  state: 'Tamil Nadu',
  panLast4: null,
  createdAt: NOW,
});

const token = (id: string, tokenHash: string) => ({
  id,
  agentId: 'agent-1',
  tokenHash,
  expiresAt: LATER,
  revokedAt: null,
  createdAt: NOW,
});

const auditEntry = (action: string) => ({
  actorId: 'admin-1',
  action,
  entity: 'agent',
  entityId: 'agent-1',
});

describe('FakeAgentUnitOfWork (AgentUnitOfWork contract)', () => {
  it('returns what the function returns', async () => {
    const { uow } = setup();
    await expect(uow.run(() => Promise.resolve(42))).resolves.toBe(42);
  });

  describe('success keeps every write', () => {
    it('keeps repository changes and the audit row', async () => {
      const { uow, agents, codes, tokens, attributions, audit } = setup();
      await uow.run(async (tx) => {
        await agents.create(newAgent(), tx);
        await codes.create(
          {
            id: 'code-1',
            agentId: 'agent-1',
            code: 'NM7K2P9X',
            isPrimary: true,
            isActive: true,
            createdAt: NOW,
          },
          tx,
        );
        await tokens.create(token('t1', 'h1'), tx);
        await attributions.create(
          {
            id: 'attr-1',
            memberId: 'member-1',
            agentId: 'agent-1',
            codeId: 'code-1',
            source: 'CODE_AT_SIGNUP',
            memberPhoneHash: null,
            attributedAt: NOW,
          },
          tx,
        );
        await audit.record(auditEntry('AGENT_CREATED'), tx);
      });
      expect(await agents.findById('agent-1')).not.toBeNull();
      expect(await codes.findByCode('NM7K2P9X')).not.toBeNull();
      expect(await tokens.findByHash('h1')).not.toBeNull();
      expect(await attributions.findByMemberId('member-1')).not.toBeNull();
      expect(audit.entries.map((e) => e.action)).toEqual(['AGENT_CREATED']);
    });
  });

  describe('a failure inside run leaves no trace', () => {
    it('undoes creates in every repository and the audit row, and rethrows', async () => {
      const { uow, agents, codes, tokens, attributions, audit } = setup();
      const boom = new Error('boom');
      await expect(
        uow.run(async (tx) => {
          await agents.create(newAgent(), tx);
          await codes.create(
            {
              id: 'code-1',
              agentId: 'agent-1',
              code: 'NM7K2P9X',
              isPrimary: true,
              isActive: true,
              createdAt: NOW,
            },
            tx,
          );
          await tokens.create(token('t1', 'h1'), tx);
          await attributions.create(
            {
              id: 'attr-1',
              memberId: 'member-1',
              agentId: 'agent-1',
              codeId: 'code-1',
              source: 'CODE_AT_SIGNUP',
              memberPhoneHash: null,
              attributedAt: NOW,
            },
            tx,
          );
          await audit.record(auditEntry('AGENT_CREATED'), tx);
          throw boom;
        }),
      ).rejects.toBe(boom);
      expect(await agents.findById('agent-1')).toBeNull();
      expect(await agents.findByPhoneHash('phone-hash-1')).toBeNull();
      expect(await codes.codeExists('NM7K2P9X')).toBe(false);
      expect(await tokens.findByHash('h1')).toBeNull();
      expect(await attributions.findByMemberId('member-1')).toBeNull();
      expect(audit.entries).toHaveLength(0);
    });

    it('restores an updated agent to its previous values', async () => {
      const { uow, agents } = setup();
      await agents.create(newAgent());
      await expect(
        uow.run(async (tx) => {
          await agents.update(
            'agent-1',
            { status: 'ACTIVE', approvedAt: NOW, name: 'Changed' },
            tx,
          );
          throw new Error('boom');
        }),
      ).rejects.toThrow('boom');
      expect(await agents.findById('agent-1')).toMatchObject({
        status: 'PENDING_APPROVAL',
        approvedAt: null,
        name: 'Ravi Kumar',
      });
    });

    it('restores a rotated token and removes its replacement', async () => {
      const { uow, tokens } = setup();
      await tokens.create(token('t1', 'h1'));
      await expect(
        uow.run(async (tx) => {
          await tokens.rotate('t1', token('t2', 'h2'), NOW, tx);
          throw new Error('boom');
        }),
      ).rejects.toThrow('boom');
      expect((await tokens.findByHash('h1'))?.revokedAt).toBeNull();
      expect(await tokens.findByHash('h2')).toBeNull();
    });

    it('restores tokens revoked for an agent', async () => {
      const { uow, tokens } = setup();
      await tokens.create(token('t1', 'h1'));
      await tokens.create(token('t2', 'h2'));
      await expect(
        uow.run(async (tx) => {
          expect(await tokens.revokeAllForAgent('agent-1', NOW, tx)).toBe(2);
          throw new Error('boom');
        }),
      ).rejects.toThrow('boom');
      expect((await tokens.findByHash('h1'))?.revokedAt).toBeNull();
      expect((await tokens.findByHash('h2'))?.revokedAt).toBeNull();
    });

    it('rolls back when a repository itself refuses (a conflict) after earlier writes', async () => {
      const { uow, agents, audit } = setup();
      await agents.create(newAgent('agent-1', 'taken'));
      await expect(
        uow.run(async (tx) => {
          await audit.record(auditEntry('FIRST'), tx);
          await agents.create(newAgent('agent-2', 'taken'), tx);
        }),
      ).rejects.toMatchObject({ reason: 'DUPLICATE_PHONE_HASH' });
      expect(audit.entries).toHaveLength(0);
      expect(await agents.findById('agent-2')).toBeNull();
    });

    it('keeps writes that happened before the transaction', async () => {
      const { uow, agents, audit } = setup();
      await agents.create(newAgent());
      await audit.record(auditEntry('BEFORE'));
      await expect(
        uow.run(async (tx) => {
          await audit.record(auditEntry('INSIDE'), tx);
          throw new Error('boom');
        }),
      ).rejects.toThrow('boom');
      expect(await agents.findById('agent-1')).not.toBeNull();
      expect(audit.entries.map((e) => e.action)).toEqual(['BEFORE']);
    });
  });

  describe('only writes given the tx are part of it', () => {
    it('an audit record written WITHOUT the tx survives a rollback', async () => {
      const { uow, audit } = setup();
      await expect(
        uow.run(async (tx) => {
          await audit.record(auditEntry('WITH_TX'), tx);
          await audit.record(auditEntry('WITHOUT_TX'));
          throw new Error('boom');
        }),
      ).rejects.toThrow('boom');
      expect(audit.entries.map((e) => e.action)).toEqual(['WITHOUT_TX']);
    });
  });

  describe('a repository change is visible inside the transaction', () => {
    it('reads see the writes made earlier in the same run', async () => {
      const { uow, agents } = setup();
      const port: AgentRepository = agents;
      await uow.run(async (tx) => {
        await port.create(newAgent(), tx);
        expect(await port.findById('agent-1', tx)).not.toBeNull();
      });
    });
  });

  describe('nested use is rejected, not joined', () => {
    it('an inner run rejects with a clear error', async () => {
      const { uow } = setup();
      await expect(
        uow.run(async () => {
          await uow.run(() => Promise.resolve());
        }),
      ).rejects.toThrow('Nested AgentUnitOfWork.run is not supported.');
    });

    it('rolls the outer transaction back when the error propagates', async () => {
      const { uow, agents } = setup();
      await expect(
        uow.run(async (tx) => {
          await agents.create(newAgent(), tx);
          await uow.run(() => Promise.resolve());
        }),
      ).rejects.toThrow('Nested');
      expect(await agents.findById('agent-1')).toBeNull();
    });

    it('a run after a finished run is fine (not mistaken for nesting)', async () => {
      const { uow } = setup();
      await uow.run(() => Promise.resolve());
      await expect(uow.run(() => Promise.resolve('ok'))).resolves.toBe('ok');
    });
  });

  describe('separate runs are independent', () => {
    it('one failing run does not undo another run that succeeds', async () => {
      const { uow, agents } = setup();
      const [failed, ok] = await Promise.allSettled([
        uow.run(async (tx) => {
          await agents.create(newAgent('agent-1', 'h1'), tx);
          await Promise.resolve();
          throw new Error('boom');
        }),
        uow.run(async (tx) => {
          await agents.create(newAgent('agent-2', 'h2'), tx);
          await Promise.resolve();
        }),
      ]);
      expect(failed.status).toBe('rejected');
      expect(ok.status).toBe('fulfilled');
      expect(await agents.findById('agent-1')).toBeNull();
      expect(await agents.findById('agent-2')).not.toBeNull();
    });
  });

  describe('the tx handle', () => {
    it('cannot be used after the run has finished', async () => {
      const { uow, agents } = setup();
      let kept: AgentTx | undefined;
      await uow.run((tx) => {
        kept = tx;
        return Promise.resolve();
      });
      expect(() => agents.create(newAgent(), kept)).toThrow(
        'The transaction has already finished.',
      );
    });

    it('a tx that the fake did not create is refused', () => {
      const { agents } = setup();
      expect(() => agents.create(newAgent(), {} as unknown as AgentTx)).toThrow(
        TypeError,
      );
    });
  });

  describe('permission checks accept the tx', () => {
    it('allow and deny the same way inside a run', async () => {
      const { uow } = setup();
      const fake = new FakeAgentPermission();
      const permission: AgentPermissionPort = fake;
      fake.grant('admin-1', { module: 'agents', action: 'approve' });
      await uow.run(async (tx) => {
        await expect(
          permission.assert(
            'admin-1',
            { module: 'agents', action: 'approve' },
            tx,
          ),
        ).resolves.toBeUndefined();
        await expect(
          permission.assert(
            'admin-1',
            { module: 'agents', action: 'reject' },
            tx,
          ),
        ).rejects.toBeInstanceOf(AgentPermissionDeniedError);
      });
    });

    it('a denial inside a run rolls the earlier writes back', async () => {
      const { uow, agents } = setup();
      const permission: AgentPermissionPort = new FakeAgentPermission();
      await expect(
        uow.run(async (tx) => {
          await agents.create(newAgent(), tx);
          await permission.assert(
            'nobody',
            { module: 'agents', action: 'approve' },
            tx,
          );
        }),
      ).rejects.toBeInstanceOf(AgentPermissionDeniedError);
      expect(await agents.findById('agent-1')).toBeNull();
    });
  });
});
