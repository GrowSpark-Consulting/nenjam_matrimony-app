import type { JobsOptions } from 'bullmq';

/**
 * Retry/retention policy applied to every queue unless a producer overrides it.
 *
 * Exponential backoff starting at 5s: 5s, 10s, 20s, 40s, 80s. That spread is
 * deliberate for third-party APIs — an immediate retry against a provider
 * that is rate-limiting or briefly down just burns an attempt.
 *
 * `removeOnComplete` keeps Redis from growing without bound while leaving a
 * recent window for debugging. Failures are kept longer (and, for email,
 * additionally copied to a DLQ) because a failed send is the thing anyone
 * actually needs to look at.
 */
export const DEFAULT_JOB_OPTIONS: JobsOptions = {
  attempts: 5,
  backoff: { type: 'exponential', delay: 5_000 },
  removeOnComplete: { age: 24 * 3600, count: 1_000 },
  removeOnFail: { age: 7 * 24 * 3600 },
};

/**
 * BullMQ priority is 1..N where LOWER runs first. Named here so call sites read
 * as intent ("this is an OTP") rather than a magic number.
 */
export const JOB_PRIORITY = {
  /** Blocks a human mid-flow — OTP, password reset, email verification. */
  CRITICAL: 1,
  /** User is waiting but not blocked — welcome, payment receipt. */
  HIGH: 2,
  /** Engagement: new match, new message, profile viewed. */
  NORMAL: 3,
  /** Batch/marketing — weekly digest. Never delays the above. */
  LOW: 4,
} as const;

export type JobPriority = (typeof JOB_PRIORITY)[keyof typeof JOB_PRIORITY];
