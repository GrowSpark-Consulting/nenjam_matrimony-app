/**
 * The bridge between the opaque `AgentTx` the services pass around and the
 * Prisma transaction client the repositories need.
 *
 * The services never look inside an `AgentTx`. The Prisma adapters hand one
 * out from `PrismaAgentUnitOfWork.run` (`asTx`) and take it back in every
 * repository method (`unwrapTx`). The handle is a small class, not the bare
 * client, so a stray object cannot pass for a transaction and a handle whose
 * `run` has finished is refused instead of writing outside the transaction.
 */
import type { Prisma } from '@app/database';
import type { AgentTx } from '../../ports/agent-unit-of-work.port';

export type PrismaTxClient = Prisma.TransactionClient;

class PrismaAgentTxHandle {
  finished = false;
  constructor(readonly client: PrismaTxClient) {}
}

/** Wraps a Prisma transaction client as an `AgentTx`. */
export function asTx(client: PrismaTxClient): AgentTx {
  return new PrismaAgentTxHandle(client) as unknown as AgentTx;
}

/** Marks the handle as finished: any later use is refused. */
export function finishTx(tx: AgentTx): void {
  if (tx instanceof PrismaAgentTxHandle) tx.finished = true;
}

/**
 * The Prisma client behind an `AgentTx`. A programmer error (a tx this
 * adapter did not create, or one whose `run` has finished) throws straight
 * away, as the in-memory fake does.
 */
export function unwrapTx(tx: AgentTx): PrismaTxClient {
  if (!(tx instanceof PrismaAgentTxHandle)) {
    throw new TypeError('tx was not created by PrismaAgentUnitOfWork.run.');
  }
  if (tx.finished) {
    throw new Error('The transaction has already finished.');
  }
  return tx.client;
}
