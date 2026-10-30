import { Injectable } from '@nestjs/common';

/** One day's work for a feature. Resolves with a small JSON-safe summary
 *  (counts, never personal data); rejects when it could not finish. */
export type DailyJob = (now: Date) => Promise<unknown>;

export interface RegisteredDailyJob {
  name: string;
  run: DailyJob;
}

/**
 * The jobs `POST /internal/jobs/daily` runs once a day, after the payment
 * event catch-up, in the order they were registered. Render runs no
 * scheduler: a GitHub Actions schedule calls that route.
 *
 * A feature registers in its module's onModuleInit:
 *
 *   registry.register('agent.daily_approval', (now) => approval.run(now, 500));
 *
 * Every job must catch up (do everything that is due, however late the run)
 * and be safe to run twice: a run can be late, missed or repeated.
 */
@Injectable()
export class DailyJobRegistry {
  private readonly jobs: RegisteredDailyJob[] = [];

  register(name: string, run: DailyJob): void {
    if (!/^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$/.test(name)) {
      throw new RangeError(
        `Daily job name "${name}" must look like "area.job_name".`,
      );
    }
    if (this.jobs.some((job) => job.name === name)) {
      throw new Error(`Daily job "${name}" is already registered.`);
    }
    this.jobs.push({ name, run });
  }

  list(): readonly RegisteredDailyJob[] {
    return [...this.jobs];
  }
}
