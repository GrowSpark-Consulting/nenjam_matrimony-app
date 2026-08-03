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
 * Dead-letter queue naming. A job that exhausts its retries is copied here
 * with its failure history so it can be inspected and replayed by hand,
 * instead of only living in BullMQ's `failed` set where it silently ages out
 * once `removeOnFail` trims it.
 */
export const DEAD_LETTER_SUFFIX = 'dlq';

export const deadLetterQueueName = (queue: QueueName): string =>
  `${queue}-${DEAD_LETTER_SUFFIX}`;

export const QUEUE_DLQ_NAMES = {
  EMAIL: deadLetterQueueName(QUEUE_NAMES.EMAIL),
} as const;
