import {
  ConflictException,
  Logger,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import type { AppConfigService } from '@app/config';
import { DailyJobRegistry } from '../platform/jobs/daily-job.registry';
import type { PaymentEventDispatcher } from '../subscription/events/payment-event-outbox';
import { DailyJobsController } from './daily-jobs.controller';
import { DailyJobsService } from './daily-jobs.service';

const NOW = new Date('2026-10-30T20:30:00Z');
const SECRET = 's'.repeat(40);

function build() {
  const calls: string[] = [];
  const dispatcher = {
    drain: jest.fn(() => {
      calls.push('payment_events.redeliver');
      return Promise.resolve({
        delivered: 2,
        failed: 0,
        waiting: 0,
        deadLettered: 0,
        subscribers: true,
      });
    }),
  };
  const registry = new DailyJobRegistry();
  const service = new DailyJobsService(
    dispatcher as unknown as PaymentEventDispatcher,
    registry,
  );
  return { service, registry, dispatcher, calls };
}

describe('DailyJobRegistry', () => {
  it('keeps jobs in registration order', () => {
    const registry = new DailyJobRegistry();
    registry.register('agent.daily_approval', () => Promise.resolve());
    registry.register('membership.expiry', () => Promise.resolve());
    expect(registry.list().map((j) => j.name)).toEqual([
      'agent.daily_approval',
      'membership.expiry',
    ]);
  });

  it('refuses a repeated or badly named job', () => {
    const registry = new DailyJobRegistry();
    registry.register('agent.daily_approval', () => Promise.resolve());
    expect(() =>
      registry.register('agent.daily_approval', () => Promise.resolve()),
    ).toThrow(/already registered/);
    expect(() =>
      registry.register('Daily Approval', () => Promise.resolve()),
    ).toThrow(RangeError);
  });
});

describe('DailyJobsService', () => {
  beforeEach(() => {
    jest.spyOn(Logger.prototype, 'log').mockImplementation(() => undefined);
    jest.spyOn(Logger.prototype, 'error').mockImplementation(() => undefined);
  });
  afterEach(() => jest.restoreAllMocks());

  it('delivers waiting payment events first, then runs each job with the same time', async () => {
    const { service, registry, calls } = build();
    const seen: Date[] = [];
    registry.register('agent.daily_approval', (now) => {
      calls.push('agent.daily_approval');
      seen.push(now);
      return Promise.resolve({ approved: 3 });
    });
    const report = await service.runAll(NOW);
    expect(calls).toEqual(['payment_events.redeliver', 'agent.daily_approval']);
    expect(seen).toEqual([NOW]);
    expect(report).toMatchObject({
      ranAt: NOW.toISOString(),
      ok: true,
      results: [
        {
          name: 'payment_events.redeliver',
          ok: true,
          detail: { delivered: 2 },
        },
        { name: 'agent.daily_approval', ok: true, detail: { approved: 3 } },
      ],
    });
  });

  it('reports a failing job and still runs the rest', async () => {
    const { service, registry, calls } = build();
    registry.register('agent.daily_approval', () =>
      Promise.reject(new Error('db timeout')),
    );
    registry.register('membership.expiry', () => {
      calls.push('membership.expiry');
      return Promise.resolve(1);
    });
    const report = await service.runAll(NOW);
    expect(report.ok).toBe(false);
    expect(report.results[1]).toMatchObject({
      name: 'agent.daily_approval',
      ok: false,
      error: 'db timeout',
    });
    expect(calls).toContain('membership.expiry');
  });

  it('refuses a second run while one is going (409)', async () => {
    const { service, registry } = build();
    let release: () => void = () => undefined;
    registry.register(
      'agent.daily_approval',
      () => new Promise<void>((resolve) => (release = resolve)),
    );
    const first = service.runAll(NOW);
    await new Promise((resolve) => setImmediate(resolve));
    await expect(service.runAll(NOW)).rejects.toBeInstanceOf(ConflictException);
    release();
    await expect(first).resolves.toMatchObject({ ok: true });
  });
});

describe('DailyJobsController', () => {
  const controller = (secret?: string) => {
    const jobs = { runAll: jest.fn().mockResolvedValue({ ok: true }) };
    return {
      jobs,
      controller: new DailyJobsController(
        jobs as unknown as DailyJobsService,
        { jobs: { secret } } as unknown as AppConfigService,
      ),
    };
  };

  it('answers 503 while JOBS_SECRET is not set', () => {
    const { controller: c, jobs } = controller(undefined);
    expect(() => c.daily(SECRET)).toThrow(ServiceUnavailableException);
    expect(jobs.runAll).not.toHaveBeenCalled();
  });

  it.each([undefined, '', 'wrong', `${SECRET}x`])(
    'refuses secret %p with 401 and runs nothing',
    (sent) => {
      const { controller: c, jobs } = controller(SECRET);
      expect(() => c.daily(sent)).toThrow(UnauthorizedException);
      expect(jobs.runAll).not.toHaveBeenCalled();
    },
  );

  it('runs the jobs with the right secret', async () => {
    const { controller: c, jobs } = controller(SECRET);
    await expect(c.daily(SECRET)).resolves.toEqual({ ok: true });
    expect(jobs.runAll).toHaveBeenCalledTimes(1);
  });
});
