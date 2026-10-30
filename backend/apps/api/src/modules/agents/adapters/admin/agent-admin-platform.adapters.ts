/**
 * The agent program's platform ports, backed by Shaaz's admin and platform
 * services. Thin on purpose: each one translates between our port and his
 * API and nothing else.
 *
 * - `AdminPermissionAdapter`: `assertAdminPermission(tx, userId, key)` from
 *   admin RBAC, run on the SAME transaction as the change. His check throws
 *   Nest's ForbiddenException; the port promises AgentPermissionDeniedError,
 *   so that is what leaves here.
 * - `AdminAuditAdapter`: `AdminAuditService.record(tx, entry)`, on the same
 *   transaction (a failed audit write rolls the change back).
 * - `IdentifierHashAdapter`: `IdentifierHashService.hashIdentifier` /
 *   `hashIdentifierAll` (503 while IDENTIFIER_HASH_PEPPERS is not set; his
 *   RangeError for a bad value becomes our VALIDATION_FAILED).
 * - `SystemClock`: the wall clock.
 */
import { ForbiddenException } from '@nestjs/common';
import type { AdminAuditService } from '../../../admin/services/admin-audit.service';
import { assertAdminPermission } from '../../../admin/rbac/assert-admin-permission';
import {
  isPermissionKey,
  type PermissionKey,
} from '../../../admin/rbac/permissions';
import type { IdentifierHashService } from '../../../platform/identifier-hash.service';
import type { PrismaClient } from '@app/database';
import { AgentServiceError } from '../../errors/agent-service-error';
import type { AgentClock } from '../../ports/agent-infra-ports';
import {
  AgentPermissionDeniedError,
  type AgentAuditEntry,
  type AgentAuditPort,
  type AgentIdentifierHasher,
  type AgentIdentifierKind,
  type AgentPermission,
  type AgentPermissionPort,
} from '../../ports/agent-platform-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor } from '../prisma/prisma-agent-tx';

export function permissionKeyOf(permission: AgentPermission): PermissionKey {
  const key = `${permission.module}.${permission.action}`;
  if (!isPermissionKey(key)) {
    // A key that is not seeded can never be held: deny, do not guess.
    throw new AgentPermissionDeniedError(permission);
  }
  return key;
}

export class AdminPermissionAdapter implements AgentPermissionPort {
  constructor(private readonly prisma: PrismaClient) {}

  async assert(
    actorId: string,
    permission: AgentPermission,
    tx?: AgentTx,
  ): Promise<void> {
    const key = permissionKeyOf(permission);
    try {
      await assertAdminPermission(dbFor(this.prisma, tx), actorId, key);
    } catch (error) {
      if (error instanceof ForbiddenException) {
        throw new AgentPermissionDeniedError(permission);
      }
      throw error;
    }
  }

  /** The same check as `assert`: only a denial is `false`; any other failure still throws. */
  async has(
    actorId: string,
    permission: AgentPermission,
    tx?: AgentTx,
  ): Promise<boolean> {
    try {
      await this.assert(actorId, permission, tx);
      return true;
    } catch (error) {
      if (error instanceof AgentPermissionDeniedError) return false;
      throw error;
    }
  }
}

export class AdminAuditAdapter implements AgentAuditPort {
  constructor(
    private readonly prisma: PrismaClient,
    private readonly audit: AdminAuditService,
  ) {}

  async record(entry: AgentAuditEntry, tx?: AgentTx): Promise<void> {
    if (!entry.action) throw new RangeError('action must be non-empty.');
    if (!entry.entity) throw new RangeError('entity must be non-empty.');
    await this.audit.record(dbFor(this.prisma, tx), {
      actorId: entry.actorId,
      actorType:
        entry.actorType ?? (entry.actorId === null ? 'SYSTEM' : 'STAFF'),
      action: entry.action,
      entity: entry.entity,
      entityId: entry.entityId,
      reason: entry.reason ?? null,
      before: (entry.before ?? null) as never,
      after: (entry.after ?? null) as never,
      ...(entry.metadata !== undefined && {
        metadata: entry.metadata as never,
      }),
      ...(entry.context !== undefined && { context: entry.context }),
    });
  }
}

export class IdentifierHashAdapter implements AgentIdentifierHasher {
  constructor(private readonly hashing: IdentifierHashService) {}

  hash(kind: AgentIdentifierKind, value: string): string {
    return invalidIdentifierAsValidation(kind, () =>
      this.hashing.hashIdentifier(kind, value),
    );
  }

  hashAll(kind: AgentIdentifierKind, value: string): string[] {
    return invalidIdentifierAsValidation(kind, () =>
      this.hashing.hashIdentifierAll(kind, value),
    );
  }
}

const IDENTIFIER_FIELD: Record<AgentIdentifierKind, string> = {
  PHONE: 'phone',
  EMAIL: 'email',
  PAN: 'pan',
};

/** His RangeError (an empty or malformed value) is the caller's mistake: our
 *  VALIDATION_FAILED naming the field, never the value. His 503 and any other
 *  error pass through unchanged. */
function invalidIdentifierAsValidation<T>(
  kind: AgentIdentifierKind,
  run: () => T,
): T {
  try {
    return run();
  } catch (error) {
    if (error instanceof RangeError) {
      throw new AgentServiceError('VALIDATION_FAILED', {
        fields: [IDENTIFIER_FIELD[kind]],
      });
    }
    throw error;
  }
}

export class SystemClock implements AgentClock {
  now(): Date {
    return new Date();
  }
}
