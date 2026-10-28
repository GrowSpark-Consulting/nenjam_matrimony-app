/**
 * In-memory transaction for tests.
 *
 * Every fake write that is given the `tx` registers an undo step; if the
 * function passed to `run` throws, the steps are run newest-first, so the
 * repositories and the audit log end up exactly as they were. A write that is
 * NOT given the `tx` is outside the transaction and is never undone, as in a
 * real database.
 */
import { AsyncLocalStorage } from 'async_hooks';
import type {
  AgentTx,
  AgentUnitOfWork,
} from '../ports/agent-unit-of-work.port';

export class FakeAgentTx {
  readonly undo: Array<() => void> = [];
  finished = false;
}

/**
 * Called by a fake before it writes. Returns a function to register the undo
 * step (a no-op when there is no `tx`). A programmer error (a tx the fake did
 * not create, or one whose `run` has finished) throws straight away.
 */
export function trackWrite(
  tx: AgentTx | undefined,
): (undo: () => void) => void {
  if (tx === undefined) return () => undefined;
  if (!(tx instanceof FakeAgentTx)) {
    throw new TypeError('tx was not created by FakeAgentUnitOfWork.run.');
  }
  if (tx.finished) {
    throw new Error('The transaction has already finished.');
  }
  return (undo) => {
    tx.undo.push(undo);
  };
}

export class FakeAgentUnitOfWork implements AgentUnitOfWork {
  private readonly current = new AsyncLocalStorage<FakeAgentTx>();

  async run<T>(fn: (tx: AgentTx) => Promise<T>): Promise<T> {
    if (this.current.getStore() !== undefined) {
      throw new Error('Nested AgentUnitOfWork.run is not supported.');
    }
    const tx = new FakeAgentTx();
    try {
      return await this.current.run(tx, () => fn(tx as unknown as AgentTx));
    } catch (error) {
      for (let i = tx.undo.length - 1; i >= 0; i--) tx.undo[i]();
      throw error;
    } finally {
      tx.finished = true;
    }
  }
}
