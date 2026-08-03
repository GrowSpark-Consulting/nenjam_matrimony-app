/**
 * Every BullMQ queue in the system, in one place.
 *
 * Queue names become Redis key prefixes (`bull:<name>:*`), so renaming one
 * orphans its in-flight jobs — treat these as a wire contract, not a label.
 */
export const QUEUE_NAMES = {
  /** Transactional + lifecycle email. Consumed by apps/worker. */
  EMAIL: 'email',
} as const;

export type QueueName = (typeof QUEUE_NAMES)[keyof typeof QUEUE_NAMES];

/**
 * Dead-lettering, as it actually works today — there is no separate DLQ queue.
 *
 * A job that exhausts its retries (or fails unrecoverably) ends up in two
 * places, which together are enough to find and replay it:
 *
 *   1. BullMQ's own `failed` set, retained for 7 days by DEFAULT_JOB_OPTIONS'
 *      `removeOnFail`, holding the job payload and its failure history.
 *   2. For email specifically, an EmailLog row moved to status DEAD_LETTER
 *      with the provider's error message — queryable long after (1) ages out,
 *      via the [status, createdAt] index.
 *
 * A genuine DLQ (re-enqueue onto `email-dlq` for manual replay) is deliberately
 * NOT implemented: nothing consumes one yet, and an unattended queue that only
 * grows is worse than the retained `failed` set. Add it alongside a replay
 * tool, not before.
 */
