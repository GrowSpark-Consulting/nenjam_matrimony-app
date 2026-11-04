import { FakeCommissionPolicyRepository } from '../testing/fake-agent-commission-repositories';
import { FakeAgentClock } from '../testing/fake-agent-infra';
import { ActivePolicyHoldDays } from './active-policy-hold-days';

const NOW = new Date('2026-10-30T09:00:00.000Z');
const DAY = 86_400_000;

const version = (n: number, holdDays: number, effectiveFrom: Date) => ({
  id: `pol-${n}`,
  version: n,
  calcType: 'PERCENTAGE' as const,
  value: 1000,
  holdDays,
  effectiveFrom,
});

describe('ActivePolicyHoldDays', () => {
  it('is null while no policy is in effect', async () => {
    const policy = new FakeCommissionPolicyRepository();
    policy.add(version(1, 14, new Date(NOW.getTime() + DAY)));
    const port = new ActivePolicyHoldDays(policy, new FakeAgentClock(NOW));
    expect(await port.getActiveHoldDays()).toBeNull();
  });

  it('gives the hold days of the version in effect now, the newest one', async () => {
    const policy = new FakeCommissionPolicyRepository();
    policy.add(version(1, 14, new Date(NOW.getTime() - 10 * DAY)));
    policy.add(version(2, 21, new Date(NOW.getTime() - DAY)));
    policy.add(version(3, 30, new Date(NOW.getTime() + DAY)));
    const port = new ActivePolicyHoldDays(policy, new FakeAgentClock(NOW));
    expect(await port.getActiveHoldDays()).toBe(21);
  });

  it('asks for the version at the clock time, so a future version starts on its day', async () => {
    const policy = new FakeCommissionPolicyRepository();
    policy.add(version(1, 14, new Date(NOW.getTime() - DAY)));
    policy.add(version(2, 30, new Date(NOW.getTime() + DAY)));
    const clock = new FakeAgentClock(NOW);
    const port = new ActivePolicyHoldDays(policy, clock);
    expect(await port.getActiveHoldDays()).toBe(14);
    clock.advance(DAY);
    expect(await port.getActiveHoldDays()).toBe(30);
  });

  it('passes 0 hold days through (0 is a value, not missing)', async () => {
    const policy = new FakeCommissionPolicyRepository();
    policy.add(version(1, 0, new Date(NOW.getTime() - DAY)));
    const port = new ActivePolicyHoldDays(policy, new FakeAgentClock(NOW));
    expect(await port.getActiveHoldDays()).toBe(0);
  });
});
