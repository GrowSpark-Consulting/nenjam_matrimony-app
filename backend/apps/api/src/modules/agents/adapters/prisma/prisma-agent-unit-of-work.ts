/**
 * `AgentUnitOfWork` on a Prisma interactive transaction.
 *
 * `run(fn)` opens `prisma.$transaction`, gives `fn` an `AgentTx` wrapping the
 * transaction client, and lets Prisma commit when `fn` resolves or roll back
 * when it rejects (the error is rethrown unchanged). Every write that was
 * given the `tx` goes with it; a write that was not is outside it.
 *
 * Nesting is refused, as the fake does. The transaction options are
 * constructor parameters; the adapter holds no values of its own. Left out,
 * Prisma uses the ones configured on the client.
 *
 * Postgres aborts a transaction when a statement fails (a unique violation
 * included): after the repositories report an `AgentConflictError`, nothing
 * more can be done with that `tx`, so a service must let the error leave
 * `run`, which rolls back.
 */
import { AsyncLocalStorage } from 'async_hooks';
import type { Prisma, PrismaClient } from '@app/database';
import type {
  AgentTx,
  AgentUnitOfWork,
} from '../../ports/agent-unit-of-work.port';
import { asTx, finishTx } from './prisma-agent-tx';

export interface PrismaAgentTransactionOptions {
  /** Longest wait to open the transaction, in milliseconds. */
  maxWaitMs?: number;
  /** Longest the transaction may run, in milliseconds. */
  timeoutMs?: number;
  isolationLevel?: Prisma.TransactionIsolationLevel;
}

export class PrismaAgentUnitOfWork implements AgentUnitOfWork {
  private readonly current = new AsyncLocalStorage<AgentTx>();

  constructor(
    private readonly prisma: Pick<PrismaClient, '$transaction'>,
    private readonly options: PrismaAgentTransactionOptions = {},
  ) {}

  async run<T>(fn: (tx: AgentTx) => Promise<T>): Promise<T> {
    if (this.current.getStore() !== undefined) {
      throw new Error('Nested AgentUnitOfWork.run is not supported.');
    }
    const { maxWaitMs, timeoutMs, isolationLevel } = this.options;
    return this.prisma.$transaction(
      async (client) => {
        const tx = asTx(client);
        try {
          return await this.current.run(tx, () => fn(tx));
        } finally {
          finishTx(tx);
        }
      },
      {
        ...(maxWaitMs !== undefined && { maxWait: maxWaitMs }),
        ...(timeoutMs !== undefined && { timeout: timeoutMs }),
        ...(isolationLevel !== undefined && { isolationLevel }),
      },
    );
  }
}
