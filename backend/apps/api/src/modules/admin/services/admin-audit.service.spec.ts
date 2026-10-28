import { Logger } from '@nestjs/common';
import { AdminAuditService } from './admin-audit.service';

describe('AdminAuditService', () => {
  const context = {
    requestId: 'req-1',
    ipAddress: '203.0.113.9',
    userAgent: 'ua',
  };

  it("writes the change's audit row in the caller's transaction, with context", async () => {
    const create = jest.fn().mockResolvedValue({});
    const outside = { auditLog: { create: jest.fn() } };
    const service = new AdminAuditService(outside as never);

    await service.record({ auditLog: { create } } as never, {
      actorId: 'user-admin',
      action: 'agent.approve',
      entity: 'Agent',
      entityId: 'agent-1',
      reason: 'documents checked',
      before: { status: 'PENDING_APPROVAL' },
      after: { status: 'ACTIVE' },
      context,
    });

    expect(outside.auditLog.create).not.toHaveBeenCalled();
    expect(create).toHaveBeenCalledWith({
      data: {
        actorId: 'user-admin',
        action: 'agent.approve',
        entity: 'Agent',
        entityId: 'agent-1',
        reason: 'documents checked',
        before: { status: 'PENDING_APPROVAL' },
        after: { status: 'ACTIVE' },
        metadata: undefined,
        requestId: 'req-1',
        ipAddress: '203.0.113.9',
        userAgent: 'ua',
      },
    });
  });

  it('propagates a failed write, so the surrounding transaction rolls back', async () => {
    const service = new AdminAuditService({} as never);
    const failing = {
      auditLog: { create: jest.fn().mockRejectedValue(new Error('down')) },
    };
    await expect(
      service.record(failing as never, {
        actorId: null,
        action: 'x.y',
        entity: 'X',
      }),
    ).rejects.toThrow('down');
  });

  it('refuses an entry without an action or entity', async () => {
    const service = new AdminAuditService({} as never);
    const tx = { auditLog: { create: jest.fn() } };
    await expect(
      service.record(tx as never, { actorId: null, action: ' ', entity: 'X' }),
    ).rejects.toBeInstanceOf(RangeError);
    expect(tx.auditLog.create).not.toHaveBeenCalled();
  });

  it('never throws from a best-effort write', async () => {
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
    const service = new AdminAuditService({
      auditLog: { create: jest.fn().mockRejectedValue(new Error('down')) },
    } as never);
    await expect(
      service.recordBestEffort({
        actorId: 'u',
        action: 'admin.access.denied',
        entity: 'AdminRoute',
      }),
    ).resolves.toBeUndefined();
  });
});
