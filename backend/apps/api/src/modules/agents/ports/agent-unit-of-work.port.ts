/**
 * Transactions for the agent program, without importing Prisma.
 */

declare const agentTxBrand: unique symbol;

/**
 * An opaque handle to an open database transaction. Services only pass it
 * along; they never look inside. The real adapter hands out its Prisma
 * transaction client under this type.
 */
export interface AgentTx {
  readonly [agentTxBrand]: true;
}

/**
 * Runs `fn` in one transaction: if `fn` throws or rejects, every write that
 * was given the `tx` is rolled back and the error is rethrown; otherwise they
 * all commit together. A write that is NOT given the `tx` is outside the
 * transaction and stays. Money and admin actions must therefore pass the
 * `tx` to their audit record too, so the audit row commits with the change.
 *
 * `run` cannot be nested: calling it inside `fn` rejects with an Error.
 * The `tx` is only valid until `fn` finishes.
 */
export interface AgentUnitOfWork {
  run<T>(fn: (tx: AgentTx) => Promise<T>): Promise<T>;
}
