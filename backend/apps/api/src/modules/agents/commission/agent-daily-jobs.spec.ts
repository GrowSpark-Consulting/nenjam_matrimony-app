import { DailyJobRegistry } from '../../platform/jobs/daily-job.registry';
import { DailyJobsService } from '../../jobs/daily-jobs.service';
import type { PaymentEventDispatcher } from '../../subscription/events/payment-event-outbox';
import {
  DAY,
  HOUR,
  T0,
  makeCommissionHarness,
  type CommissionHarness,
} from '../testing/agent-commission-harness';
import {
  AGENT_DAILY_APPROVAL_BATCH_SIZE,
  AGENT_DAILY_APPROVAL_JOB,
  registerAgentDailyJobs,
} from './agent-daily-jobs';

const HOLD_END = new Date(T0.getTime() + HOUR + 14 * DAY);

let h: CommissionHarness;
let registry: DailyJobRegistry;

beforeEach(() => {
  h = makeCommissionHarness();
  h.seedPolicy();
  registry = new DailyJobRegistry();
  registerAgentDailyJobs(registry, h.approval);
});

const jobsService = () =>
  new DailyJobsService(
    {
      drain: jest.fn().mockResolvedValue({}),
    } as unknown as PaymentEventDispatcher,
    registry,
  );

describe('agent daily jobs', () => {
  it('registers agent.daily_approval', () => {
    expect(registry.list().map((j) => j.name)).toEqual([
      'agent.daily_approval',
    ]);
    expect(AGENT_DAILY_APPROVAL_JOB).toBe('agent.daily_approval');
  });

  it('runs the approval with the named batch size', async () => {
    const spy = jest.fn().mockResolvedValue({ examined: 0 });
    const r = new DailyJobRegistry();
    registerAgentDailyJobs(r, { runDailyApproval: spy });
    const now = new Date(T0);
    await r.list()[0].run(now);
    expect(spy).toHaveBeenCalledWith(now, AGENT_DAILY_APPROVAL_BATCH_SIZE);
  });

  it('approves a commission whose hold has ended and credits the ledger', async () => {
    await h.seedCommission(1);
    const report = await jobsService().runAll(HOLD_END);
    expect(report.ok).toBe(true);
    expect((await h.commissions.findByPaymentId('pay-1'))?.status).toBe(
      'APPROVED',
    );
    expect(await h.ledger.balance('agent-1')).toBeGreaterThan(0);
  });

  it('is safe to run twice: the second run credits nothing more', async () => {
    await h.seedCommission(1);
    await jobsService().runAll(HOLD_END);
    const balance = await h.ledger.balance('agent-1');
    const second = await jobsService().runAll(
      new Date(HOLD_END.getTime() + HOUR),
    );
    expect(second.ok).toBe(true);
    expect(await h.ledger.balance('agent-1')).toBe(balance);
  });

  it('catches up after a two-day gap', async () => {
    await h.seedCommission(1);
    await h.seedCommission(2);
    // Nothing ran on the day the holds ended or the day after.
    const late = new Date(HOLD_END.getTime() + 2 * DAY);
    await jobsService().runAll(late);
    expect((await h.commissions.findByPaymentId('pay-1'))?.status).toBe(
      'APPROVED',
    );
    expect((await h.commissions.findByPaymentId('pay-2'))?.status).toBe(
      'APPROVED',
    );
  });

  it('a failing job does not stop the others', async () => {
    const failing = new DailyJobRegistry();
    failing.register('agent.daily_approval', () =>
      Promise.reject(new Error('settings missing')),
    );
    const after = jest.fn().mockResolvedValue({ done: true });
    failing.register('other.job', after);
    const svc = new DailyJobsService(
      {
        drain: jest.fn().mockResolvedValue({}),
      } as unknown as PaymentEventDispatcher,
      failing,
    );
    const report = await svc.runAll(HOLD_END);
    expect(report.ok).toBe(false);
    expect(report.results.map((r) => [r.name, r.ok])).toEqual([
      ['payment_events.redeliver', true],
      ['agent.daily_approval', false],
      ['other.job', true],
    ]);
    expect(after).toHaveBeenCalled();
  });

  it('reports the approval as failed (not silently ok) when a required setting is missing', async () => {
    const bare = makeCommissionHarness({});
    const r = new DailyJobRegistry();
    registerAgentDailyJobs(r, bare.approval);
    const svc = new DailyJobsService(
      {
        drain: jest.fn().mockResolvedValue({}),
      } as unknown as PaymentEventDispatcher,
      r,
    );
    const report = await svc.runAll(HOLD_END);
    expect(report.results[1]).toMatchObject({
      name: 'agent.daily_approval',
      ok: false,
    });
  });
});
