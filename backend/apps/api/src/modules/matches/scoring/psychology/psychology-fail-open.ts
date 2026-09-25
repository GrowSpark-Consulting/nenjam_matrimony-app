/**
 * Primitives for keeping psychology off Discover's failure path.
 *
 * Psychology is an optional ranking signal. Nothing here makes it more
 * reliable — it makes its unreliability invisible to the member: a lookup that
 * fails, stalls or is known-broken costs the request a bounded amount of time
 * and then the feed is ranked without it.
 */

export class PsychologyTimeoutError extends Error {
  constructor(ms: number) {
    super(`psychology lookup exceeded its ${ms}ms budget`);
    this.name = 'PsychologyTimeoutError';
  }
}

/**
 * Rejects with PsychologyTimeoutError if `promise` hasn't settled within `ms`.
 *
 * This bounds how long the REQUEST waits; it cannot cancel the underlying
 * query, which keeps its pool connection until the pool's own
 * statement_timeout fires. That is why a circuit breaker sits alongside it —
 * without one, a slow database would accumulate abandoned queries.
 */
export function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new PsychologyTimeoutError(ms)), ms);
    // Never keep the process alive just for this timer.
    timer.unref?.();
  });
  // If the timeout wins, the original promise may still reject later; without
  // this that becomes an unhandled rejection.
  promise.catch(() => undefined);
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

/**
 * Stops issuing psychology queries after repeated consecutive failures.
 *
 * closed → open after `threshold` consecutive failures → after `openMs` one
 * trial call is let through (half-open): success closes it, another failure
 * re-opens it immediately. In-process state, per API instance — enough,
 * because the point is to protect that instance's own connection pool.
 */
export class PsychologyCircuitBreaker {
  private consecutiveFailures = 0;
  private openedAt: number | null = null;

  constructor(
    private readonly threshold = 3,
    private readonly openMs = 30_000,
  ) {}

  allow(now: number = Date.now()): boolean {
    if (this.openedAt === null) return true;
    // Half-open: let a trial through once the cool-down has passed.
    return now - this.openedAt >= this.openMs;
  }

  recordSuccess(): void {
    this.consecutiveFailures = 0;
    this.openedAt = null;
  }

  recordFailure(now: number = Date.now()): void {
    this.consecutiveFailures += 1;
    if (this.consecutiveFailures >= this.threshold) this.openedAt = now;
  }

  get isOpen(): boolean {
    return this.openedAt !== null;
  }
}
