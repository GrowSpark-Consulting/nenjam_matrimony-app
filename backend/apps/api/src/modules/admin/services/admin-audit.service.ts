import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type { Prisma } from '../../../../../../libs/database/generated/client';
import type { AdminRequestContext } from '../auth/admin-request';

export interface AdminAuditEntry {
  /** The acting user's id, derived from the verified token — never from a
   *  request body. Null for the system or the provisioning script. */
  actorId: string | null;
  /** `<area>.<event>`, e.g. `admin.session.created`, `agent.approve`. */
  action: string;
  entity: string;
  entityId?: string | null;
  /** The typed reason a sensitive change requires. */
  reason?: string | null;
  /** JSON-safe snapshots (no Dates or class instances). */
  before?: Prisma.InputJsonValue | null;
  after?: Prisma.InputJsonValue | null;
  /** Never tokens, OTPs, passwords, full PAN or bank details. */
  metadata?: Prisma.InputJsonObject;
  context?: AdminRequestContext;
}

type AuditWriter = Pick<Prisma.TransactionClient, 'auditLog'>;

/**
 * The single writer of admin audit rows. There is deliberately no update or
 * delete here, nor any route that edits audit rows.
 */
@Injectable()
export class AdminAuditService {
  private readonly logger = new Logger(AdminAuditService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Writes the row in the caller's transaction, so a change and its audit row
   * commit together or not at all — an audit failure rolls the change back.
   * Use this for every state change.
   */
  async record(tx: AuditWriter, entry: AdminAuditEntry): Promise<void> {
    await tx.auditLog.create({ data: toRow(entry) });
  }

  /**
   * For events that change nothing else — a refused request, a wrong code —
   * where there is no transaction to join. Never throws: failing to record a
   * denial must not turn it into a 500.
   */
  async recordBestEffort(entry: AdminAuditEntry): Promise<void> {
    try {
      await this.prisma.auditLog.create({ data: toRow(entry) });
    } catch (error) {
      this.logger.error(
        `Could not write audit row "${entry.action}": ${(error as Error).message}`,
      );
    }
  }
}

function toRow(entry: AdminAuditEntry): Prisma.AuditLogUncheckedCreateInput {
  if (!entry.action?.trim() || !entry.entity?.trim()) {
    throw new RangeError('An audit entry needs an action and an entity.');
  }
  return {
    actorId: entry.actorId,
    action: entry.action,
    entity: entry.entity,
    entityId: entry.entityId ?? null,
    reason: entry.reason ?? null,
    before: json(entry.before),
    after: json(entry.after),
    metadata: json(entry.metadata),
    requestId: entry.context?.requestId ?? null,
    ipAddress: entry.context?.ipAddress ?? null,
    userAgent: entry.context?.userAgent ?? null,
  };
}

/** Prisma needs `undefined` (column default, i.e. NULL) rather than `null`
 *  for an absent JSON value. */
function json(
  value: Prisma.InputJsonValue | null | undefined,
): Prisma.InputJsonValue | undefined {
  return value ?? undefined;
}
