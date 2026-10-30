import { ConflictException, Injectable, Logger } from '@nestjs/common';
import { DailyJobRegistry } from '../platform/jobs/daily-job.registry';
import { PaymentEventDispatcher } from '../subscription/events/payment-event-outbox';

export interface DailyJobResult {
  name: string;
  ok: boolean;
  durationMs: number;
  /** The job's own summary (counts). */
  detail?: unknown;
  error?: string;
}

export interface DailyRunReport {
  ranAt: string;
  ok: boolean;
  results: DailyJobResult[];
}

const MAX_ERROR_LENGTH = 300;

/**
 * The once-a-day run: first the payment event catch-up (events a restart or
 * a failing handler left undelivered), then every job registered with
 * DailyJobRegistry, in order. A failing job is reported and the rest still
 * run. One run at a time per process.
 */
@Injectable()
export class DailyJobsService {
  private readonly logger = new Logger(DailyJobsService.name);
  private running = false;

  constructor(
    private readonly dispatcher: PaymentEventDispatcher,
    private readonly registry: DailyJobRegistry,
  ) {}

  async runAll(now: Date = new Date()): Promise<DailyRunReport> {
    if (this.running) {
      throw new ConflictException({
        statusCode: 409,
        error: 'Conflict',
        code: 'DAILY_JOBS_RUNNING',
        message: 'The daily jobs are already running.',
      });
    }
    this.running = true;
    try {
      const results = [
        await this.runOne('payment_events.redeliver', () =>
          this.dispatcher.drain(),
        ),
      ];
      for (const job of this.registry.list()) {
        results.push(await this.runOne(job.name, () => job.run(now)));
      }
      const report = {
        ranAt: now.toISOString(),
        ok: results.every((r) => r.ok),
        results,
      };
      this.logger.log(
        `Daily jobs: ${results.map((r) => `${r.name}=${r.ok ? 'ok' : 'FAILED'}`).join(', ')}`,
      );
      return report;
    } finally {
      this.running = false;
    }
  }

  private async runOne(
    name: string,
    run: () => Promise<unknown>,
  ): Promise<DailyJobResult> {
    const started = Date.now();
    try {
      const detail = await run();
      return {
        name,
        ok: true,
        durationMs: Date.now() - started,
        detail: detail ?? null,
      };
    } catch (error) {
      const message = (error as Error).message ?? String(error);
      this.logger.error(`Daily job ${name} failed: ${message}`);
      return {
        name,
        ok: false,
        durationMs: Date.now() - started,
        error: message.slice(0, MAX_ERROR_LENGTH),
      };
    }
  }
}
