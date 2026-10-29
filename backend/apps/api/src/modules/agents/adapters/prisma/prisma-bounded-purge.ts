/**
 * Shared settings and failure handling for the opportunistic purge of
 * expired rows (applicants, code-validation attempts). There is no scheduler:
 * a write deletes a small, limited batch of rows that are already worthless.
 *
 * Rules that both stores follow:
 * - The batch size and the grace period are constructor parameters, never
 *   constants, and a bad value is refused at construction.
 * - The purge runs on the plain client, not on the caller's transaction: a
 *   failed purge statement would otherwise abort the caller's transaction
 *   (Postgres refuses every later statement), and housekeeping must never
 *   fail the write that triggered it.
 * - A purge failure is swallowed and logged with a fixed message and the
 *   error's class name only: no row, key, phone hash or error text.
 */
import { Logger } from '@nestjs/common';
import type { AgentClock } from '../../ports/agent-infra-ports';

export interface BoundedPurgeOptions {
  /** Most rows one write may delete. A positive integer. */
  batchSize: number;
  /** How long past its expiry a row is kept before it may be purged, in milliseconds. 0 or more. */
  graceMs: number;
  clock: AgentClock;
  /** Where a purge failure is reported. Defaults to a Nest logger. */
  logger?: { warn(message: string): void };
}

export function checkPurgeOptions(options: BoundedPurgeOptions): void {
  if (!Number.isInteger(options.batchSize) || options.batchSize < 1) {
    throw new RangeError('purge batchSize must be a positive integer.');
  }
  if (!Number.isFinite(options.graceMs) || options.graceMs < 0) {
    throw new RangeError('purge graceMs must be zero or more.');
  }
}

/** Runs `purge`; any failure is logged without values and never rethrown. */
export async function runPurge(
  options: BoundedPurgeOptions,
  what: string,
  purge: (cutoff: Date, batchSize: number) => Promise<void>,
): Promise<void> {
  try {
    const cutoff = new Date(options.clock.now().getTime() - options.graceMs);
    await purge(cutoff, options.batchSize);
  } catch (error) {
    const logger = options.logger ?? new Logger('AgentPurge');
    const kind = error instanceof Error ? error.constructor.name : 'Error';
    logger.warn(
      `Purge of expired ${what} failed (${kind}); the write went on.`,
    );
  }
}
