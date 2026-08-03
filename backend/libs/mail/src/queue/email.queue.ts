import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import { Queue } from 'bullmq';
import { QUEUE_NAMES } from '@app/queue';
import type { EmailJobData } from '../interfaces/email.interface';
import { EMAIL_TYPE_DEFINITIONS } from '../types/email-type.enum';

export interface EnqueueOptions {
  /** Milliseconds to hold the job before it becomes eligible. Used for
   *  "nudge" style mail (e.g. remind me in 24h). */
  delayMs?: number;
  /** Collapses duplicates: BullMQ ignores a job whose id already exists.
   *  Pass a deterministic key (e.g. `digest:<userId>:<isoWeek>`) to make an
   *  at-least-once caller effectively at-most-once. */
  dedupeKey?: string;
}

/**
 * The only way a job reaches the email queue.
 *
 * Thin on purpose — it owns queue mechanics (priority, delay, dedupe) and
 * nothing else. Business rules live in MailService above it; delivery lives
 * in the processor below it.
 */
@Injectable()
export class EmailQueue {
  private readonly logger = new Logger(EmailQueue.name);

  constructor(
    @InjectQueue(QUEUE_NAMES.EMAIL) private readonly queue: Queue<EmailJobData>,
  ) {}

  async enqueue(
    data: EmailJobData,
    options: EnqueueOptions = {},
  ): Promise<string | undefined> {
    const { priority } = EMAIL_TYPE_DEFINITIONS[data.emailType];

    const job = await this.queue.add(data.emailType, data, {
      priority,
      ...(options.delayMs ? { delay: options.delayMs } : {}),
      ...(options.dedupeKey ? { jobId: options.dedupeKey } : {}),
    });

    this.logger.debug(
      `Queued ${data.emailType} as job ${job.id} (priority=${priority}` +
        `${options.delayMs ? `, delay=${options.delayMs}ms` : ''}).`,
    );
    return job.id;
  }

  /** Queue depth by state — for a health endpoint or an ops dashboard. */
  async stats(): Promise<Record<string, number>> {
    return this.queue.getJobCounts(
      'waiting',
      'active',
      'completed',
      'failed',
      'delayed',
    );
  }
}
