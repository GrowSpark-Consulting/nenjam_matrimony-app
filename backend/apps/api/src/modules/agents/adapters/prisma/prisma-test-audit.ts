/**
 * A minimal `AgentAuditPort` on the existing `audit_logs` table, used only by
 * the database-gated specs to prove that an audit row written with the `tx`
 * rolls back with the change it describes. The real audit adapter waits for
 * Shaaz's `AdminAuditService` (PR #129). Never imported by production code.
 */
import type { PrismaClient } from '@app/database';
import type {
  AgentAuditEntry,
  AgentAuditPort,
} from '../../ports/agent-platform-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from './prisma-agent-tx';

export class PrismaTestAudit implements AgentAuditPort {
  constructor(private readonly prisma: PrismaClient) {}

  async record(entry: AgentAuditEntry, tx?: AgentTx): Promise<void> {
    if (!entry.action) throw new RangeError('action must be non-empty.');
    if (!entry.entity) throw new RangeError('entity must be non-empty.');
    await dbFor(this.prisma, tx).auditLog.create({
      data: {
        actorId: entry.actorId,
        action: entry.action,
        entity: entry.entity,
        entityId: entry.entityId,
        // JSON-safe by contract: no tokens, PAN or bank details.
        metadata: (entry.metadata ?? undefined) as never,
      },
    });
  }
}
