import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '@app/database';
import type { Prisma } from '../../../../../../libs/database/generated/client';

/** Chat audit actions, written to the shared `audit_logs` table. */
export const ChatAuditAction = {
  conversationCreate: 'chat.conversation.create',
  block: 'chat.conversation.block',
  unblock: 'chat.conversation.unblock',
  messageSend: 'chat.message.send',
  messageEdit: 'chat.message.edit',
  messageDelete: 'chat.message.delete',
  attachmentUpload: 'chat.attachment.upload',
  authzDenied: 'chat.authz.denied',
} as const;

export type ChatAuditActionValue =
  (typeof ChatAuditAction)[keyof typeof ChatAuditAction];

export interface AuditEntry {
  actorId?: string | null;
  action: ChatAuditActionValue;
  entity: string;
  entityId?: string | null;
  metadata?: Record<string, unknown>;
}

/**
 * Append-only audit trail for chat, backed by the existing `AuditLog` table.
 *
 * Every write is fire-and-forget: auditing is a side effect that must never
 * fail, slow, or roll back a user action, so callers invoke it as
 * `void audit.record(...)` AFTER the domain operation has committed, and a
 * failed insert is swallowed with a warning rather than propagated. That's the
 * right trade-off for an observability trail — a missed audit row is far less
 * harmful than a message send that 500s because the log write hiccuped.
 */
@Injectable()
export class ChatAuditService {
  private readonly logger = new Logger(ChatAuditService.name);

  constructor(private readonly prisma: PrismaService) {}

  async record(entry: AuditEntry): Promise<void> {
    try {
      await this.prisma.auditLog.create({
        data: {
          actorId: entry.actorId ?? null,
          action: entry.action,
          entity: entry.entity,
          entityId: entry.entityId ?? null,
          metadata: (entry.metadata ?? undefined) as
            Prisma.InputJsonValue | undefined,
        },
      });
    } catch (error) {
      this.logger.warn(
        `audit write failed (${entry.action}): ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  /** Convenience for the denial path — records who was refused what and why. */
  recordDenied(
    actorId: string | null,
    entity: string,
    entityId: string | null,
    reason: string,
    extra?: Record<string, unknown>,
  ): void {
    void this.record({
      actorId,
      action: ChatAuditAction.authzDenied,
      entity,
      entityId,
      metadata: { reason, ...extra },
    });
  }
}
