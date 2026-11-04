import { BadRequestException, ForbiddenException } from '@nestjs/common';
import type { PrismaClient } from '@app/database';
import type { AdminAuditService } from '../../../admin/services/admin-audit.service';
import type { IdentifierHashService } from '../../../platform/identifier-hash.service';
import { AgentServiceError } from '../../errors/agent-service-error';
import { AgentPermissionDeniedError } from '../../ports/agent-platform-ports';
import { asTx } from '../prisma/prisma-agent-tx';
import {
  AdminAuditAdapter,
  AdminPermissionAdapter,
  IdentifierHashAdapter,
  permissionKeyOf,
} from './agent-admin-platform.adapters';

const assertAdminPermission = jest.fn<Promise<void>, unknown[]>();
jest.mock('../../../admin/rbac/assert-admin-permission', () => ({
  assertAdminPermission: (...args: unknown[]) => assertAdminPermission(...args),
}));

const prisma = { marker: 'root-client' } as unknown as PrismaClient;
const txClient = { marker: 'tx-client' };

beforeEach(() => assertAdminPermission.mockReset());

describe('AdminPermissionAdapter (over assertAdminPermission)', () => {
  const adapter = new AdminPermissionAdapter(prisma);
  const approve = { module: 'agent', action: 'approve' };

  it('checks the key on the TRANSACTION client when given a tx', async () => {
    assertAdminPermission.mockResolvedValue(undefined);
    await adapter.assert('user-1', approve, asTx(txClient as never));
    expect(assertAdminPermission).toHaveBeenCalledWith(
      txClient,
      'user-1',
      'agent.approve',
    );
  });

  it('uses the plain client without a tx', async () => {
    assertAdminPermission.mockResolvedValue(undefined);
    await adapter.assert('user-1', approve);
    expect(assertAdminPermission.mock.calls[0][0]).toBe(prisma);
  });

  it('turns his ForbiddenException into AgentPermissionDeniedError', async () => {
    assertAdminPermission.mockRejectedValue(new ForbiddenException('no'));
    await expect(adapter.assert('user-1', approve)).rejects.toBeInstanceOf(
      AgentPermissionDeniedError,
    );
  });

  it('lets any other error through unchanged', async () => {
    const boom = new Error('database down');
    assertAdminPermission.mockRejectedValue(boom);
    await expect(adapter.assert('user-1', approve)).rejects.toBe(boom);
    const bad = new BadRequestException('x');
    assertAdminPermission.mockRejectedValue(bad);
    await expect(adapter.assert('user-1', approve)).rejects.toBe(bad);
  });

  it('has() answers true when held and false when denied, on the TRANSACTION client', async () => {
    assertAdminPermission.mockResolvedValueOnce(undefined);
    await expect(
      adapter.has('user-1', approve, asTx(txClient as never)),
    ).resolves.toBe(true);
    expect(assertAdminPermission).toHaveBeenCalledWith(
      txClient,
      'user-1',
      'agent.approve',
    );
    assertAdminPermission.mockRejectedValueOnce(new ForbiddenException('no'));
    await expect(adapter.has('user-1', approve)).resolves.toBe(false);
    await expect(
      adapter.has('user-1', { module: 'agent', action: 'everything' }),
    ).resolves.toBe(false);
  });

  it('has() lets any other error through (a failure is not a "no")', async () => {
    const boom = new Error('database down');
    assertAdminPermission.mockRejectedValueOnce(boom);
    await expect(adapter.has('user-1', approve)).rejects.toBe(boom);
  });

  it('a key that is not a seeded permission is denied without asking', async () => {
    await expect(
      adapter.assert('user-1', { module: 'agent', action: 'everything' }),
    ).rejects.toBeInstanceOf(AgentPermissionDeniedError);
    expect(assertAdminPermission).not.toHaveBeenCalled();
    expect(() => permissionKeyOf({ module: 'x', action: 'y' })).toThrow(
      AgentPermissionDeniedError,
    );
    expect(permissionKeyOf({ module: 'agent', action: 'view' })).toBe(
      'agent.view',
    );
  });
});

describe('AdminAuditAdapter (over AdminAuditService.record)', () => {
  const record = jest
    .fn<Promise<void>, [unknown, { actorType: string }]>()
    .mockResolvedValue(undefined);
  const adapter = new AdminAuditAdapter(prisma, {
    record,
  } as unknown as AdminAuditService);

  beforeEach(() => record.mockClear());

  it('writes on the TRANSACTION client with every field', async () => {
    await adapter.record(
      {
        actorId: 'user-1',
        actorType: 'STAFF',
        action: 'agent.approve',
        entity: 'Agent',
        entityId: 'agent-1',
        reason: 'Checked.',
        before: { status: 'PENDING_APPROVAL' },
        after: { status: 'ACTIVE' },
        metadata: { code: 'issued' },
        context: { requestId: 'req-1', ipAddress: '127.0.0.1' },
      },
      asTx(txClient as never),
    );
    expect(record).toHaveBeenCalledWith(txClient, {
      actorId: 'user-1',
      actorType: 'STAFF',
      action: 'agent.approve',
      entity: 'Agent',
      entityId: 'agent-1',
      reason: 'Checked.',
      before: { status: 'PENDING_APPROVAL' },
      after: { status: 'ACTIVE' },
      metadata: { code: 'issued' },
      context: { requestId: 'req-1', ipAddress: '127.0.0.1' },
    });
  });

  it('a system entry (no actor) is SYSTEM; a staff entry defaults to STAFF', async () => {
    await adapter.record({
      actorId: null,
      action: 'a',
      entity: 'E',
      entityId: null,
    });
    await adapter.record({
      actorId: 'u',
      action: 'a',
      entity: 'E',
      entityId: null,
    });
    expect(record.mock.calls.map((c) => c[1].actorType)).toEqual([
      'SYSTEM',
      'STAFF',
    ]);
  });

  it('a failed audit write fails the caller (so its transaction rolls back)', async () => {
    record.mockRejectedValueOnce(new Error('audit down'));
    await expect(
      adapter.record({
        actorId: 'u',
        action: 'a',
        entity: 'E',
        entityId: null,
      }),
    ).rejects.toThrow('audit down');
  });

  it('refuses an empty action or entity', async () => {
    await expect(
      adapter.record({ actorId: 'u', action: '', entity: 'E', entityId: null }),
    ).rejects.toThrow(RangeError);
    await expect(
      adapter.record({ actorId: 'u', action: 'a', entity: '', entityId: null }),
    ).rejects.toThrow(RangeError);
    expect(record).not.toHaveBeenCalled();
  });
});

describe('IdentifierHashAdapter (over IdentifierHashService)', () => {
  it('passes the kind and value through, and lets his 503 through', () => {
    const service = {
      hashIdentifier: jest.fn().mockReturnValue('v1:x'),
      hashIdentifierAll: jest.fn().mockReturnValue(['v1:x', 'v0:y']),
    };
    const adapter = new IdentifierHashAdapter(
      service as unknown as IdentifierHashService,
    );
    expect(adapter.hash('PHONE', '+919000000001')).toBe('v1:x');
    expect(adapter.hashAll('PHONE', '+919000000001')).toEqual(['v1:x', 'v0:y']);
    expect(service.hashIdentifierAll).toHaveBeenCalledWith(
      'PHONE',
      '+919000000001',
    );
    const unavailable = new Error('IDENTIFIER_HASHING_UNAVAILABLE');
    service.hashIdentifierAll.mockImplementation(() => {
      throw unavailable;
    });
    expect(() => adapter.hashAll('PHONE', '+919000000001')).toThrow(
      unavailable,
    );
  });

  it('turns his RangeError into VALIDATION_FAILED naming the field, never the value', () => {
    const service = {
      hashIdentifier: jest.fn(() => {
        throw new RangeError('not a phone');
      }),
      hashIdentifierAll: jest.fn(() => {
        throw new RangeError('not a PAN');
      }),
    };
    const adapter = new IdentifierHashAdapter(
      service as unknown as IdentifierHashService,
    );
    const caught = (run: () => unknown): AgentServiceError => {
      try {
        run();
      } catch (error) {
        return error as AgentServiceError;
      }
      throw new Error('expected a throw');
    };
    const phone = caught(() => adapter.hash('PHONE', 'x'));
    expect(phone).toBeInstanceOf(AgentServiceError);
    expect(phone.code).toBe('VALIDATION_FAILED');
    expect(phone.fields).toEqual(['phone']);
    expect(phone.message).not.toContain('x');
    expect(caught(() => adapter.hashAll('PAN', 'x')).fields).toEqual(['pan']);
    expect(caught(() => adapter.hash('EMAIL', 'x')).fields).toEqual(['email']);
  });
});
