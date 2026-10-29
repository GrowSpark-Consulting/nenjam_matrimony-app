/**
 * `AgentRefreshTokenRepository` on the `agent_refresh_tokens` table.
 *
 * `rotate` is the security-sensitive method: refresh tokens are one-use, and
 * two requests presenting the same token at once must not both succeed. It
 * revokes the current token with ONE conditional update
 * (`WHERE id = ? AND revoked_at IS NULL`) and stores the next token only if
 * that update changed a row. Postgres decides the race: exactly one
 * concurrent caller gets a count of 1; the other gets 0 and
 * `AgentConflictError('ALREADY_REVOKED')`, with nothing stored. Given no
 * `tx`, the revoke and the insert run in a transaction of their own so a
 * failed insert cannot leave the old token revoked.
 */
import type { PrismaClient } from '@app/database';
import type {
  AgentRefreshTokenRecord,
  AgentRefreshTokenRepository,
} from '../../ports/agent-data-ports';
import { AgentConflictError } from '../../ports/agent-data-ports';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';
import { dbFor, type PrismaTxClient } from './prisma-agent-tx';
import {
  withConflictMapping,
  type UniqueViolationRule,
} from './prisma-unique-violation';

export const REFRESH_TOKEN_UNIQUE_RULES: readonly UniqueViolationRule[] = [
  {
    constraint: 'agent_refresh_tokens_pkey',
    fields: ['id'],
    reason: 'DUPLICATE_ID',
  },
];

interface TokenRow {
  id: string;
  agentId: string;
  tokenHash: string;
  expiresAt: Date;
  revokedAt: Date | null;
  createdAt: Date;
}

function toRecord(row: TokenRow): AgentRefreshTokenRecord {
  return {
    id: row.id,
    agentId: row.agentId,
    tokenHash: row.tokenHash,
    expiresAt: row.expiresAt,
    revokedAt: row.revokedAt,
    createdAt: row.createdAt,
  };
}

export class PrismaAgentRefreshTokenRepository implements AgentRefreshTokenRepository {
  constructor(private readonly prisma: PrismaClient) {}

  create(
    token: AgentRefreshTokenRecord,
    tx?: AgentTx,
  ): Promise<AgentRefreshTokenRecord> {
    return withConflictMapping(REFRESH_TOKEN_UNIQUE_RULES, () =>
      this.insert(dbFor(this.prisma, tx), token),
    );
  }

  async findByHash(
    tokenHash: string,
    tx?: AgentTx,
  ): Promise<AgentRefreshTokenRecord | null> {
    const row = await dbFor(this.prisma, tx).agentRefreshToken.findUnique({
      where: { tokenHash },
    });
    return row ? toRecord(row) : null;
  }

  rotate(
    currentId: string,
    next: AgentRefreshTokenRecord,
    at: Date,
    tx?: AgentTx,
  ): Promise<AgentRefreshTokenRecord> {
    const rotateIn = (db: PrismaTxClient) =>
      withConflictMapping(REFRESH_TOKEN_UNIQUE_RULES, async () => {
        const { count } = await db.agentRefreshToken.updateMany({
          where: { id: currentId, revokedAt: null },
          data: { revokedAt: at },
        });
        if (count === 0) {
          const exists = await db.agentRefreshToken.findUnique({
            where: { id: currentId },
            select: { id: true },
          });
          if (exists === null) {
            throw new Error(`Unknown token ${currentId}`);
          }
          throw new AgentConflictError('ALREADY_REVOKED');
        }
        return this.insert(db, next);
      });
    return tx === undefined
      ? this.prisma.$transaction((db) => rotateIn(db))
      : rotateIn(dbFor(this.prisma, tx));
  }

  async revoke(tokenId: string, at: Date, tx?: AgentTx): Promise<boolean> {
    const { count } = await dbFor(this.prisma, tx).agentRefreshToken.updateMany(
      { where: { id: tokenId, revokedAt: null }, data: { revokedAt: at } },
    );
    return count > 0;
  }

  async revokeAllForAgent(
    agentId: string,
    at: Date,
    tx?: AgentTx,
  ): Promise<number> {
    const { count } = await dbFor(this.prisma, tx).agentRefreshToken.updateMany(
      { where: { agentId, revokedAt: null }, data: { revokedAt: at } },
    );
    return count;
  }

  private async insert(
    db: PrismaTxClient,
    token: AgentRefreshTokenRecord,
  ): Promise<AgentRefreshTokenRecord> {
    const row = await db.agentRefreshToken.create({
      data: {
        id: token.id,
        agentId: token.agentId,
        tokenHash: token.tokenHash,
        expiresAt: token.expiresAt,
        revokedAt: token.revokedAt,
        createdAt: token.createdAt,
      },
    });
    return toRecord(row);
  }
}
