import { describe, expect, it } from 'vitest';
import { describeValue, sameValue } from './entitlements';
import { formatPaise, paiseToRupeesInput, rupeesToPaise } from './format';
import { can, homeFor, visibleNav } from './permissions';
import type { FeatureDescriptor } from './types';

describe('money', () => {
  it('converts typed rupees to integer paise', () => {
    expect(rupeesToPaise('3999')).toBe(399900);
    expect(rupeesToPaise('₹3,999.5')).toBe(399950);
    expect(rupeesToPaise(' 0.01 ')).toBe(1);
    expect(rupeesToPaise('')).toBeNull();
  });

  it('refuses amounts that are not positive rupees with at most two decimals', () => {
    for (const bad of ['0', '-5', '12.345', 'abc', '1e3']) {
      expect(Number.isNaN(rupeesToPaise(bad))).toBe(true);
    }
  });

  it('round-trips paise to the input text', () => {
    expect(paiseToRupeesInput(399900)).toBe('3999');
    expect(paiseToRupeesInput(399950)).toBe('3999.50');
    expect(paiseToRupeesInput(null)).toBe('');
    expect(rupeesToPaise(paiseToRupeesInput(123405))).toBe(123405);
  });

  it('formats paise as rupees', () => {
    expect(formatPaise(399900)).toBe('₹3,999');
    expect(formatPaise(null)).toBe('Not priced');
  });
});

describe('navigation', () => {
  it('shows only sections the admin holds the permission for', () => {
    const hrefs = visibleNav(['plan.view', 'audit.view']).map((n) => n.href);
    expect(hrefs).toEqual(['/plans/', '/audit/']);
    expect(homeFor(['subscription.view'])).toBe('/subscriptions/');
    expect(homeFor([])).toBeNull();
    expect(can(undefined, 'plan.view')).toBe(false);
  });
});

describe('entitlements', () => {
  const quota: FeatureDescriptor = {
    key: 'interests.send',
    kind: 'quota',
    section: 'INTERESTS',
    label: 'Sending interests',
    period: 'MONTH',
  };
  const contacts: FeatureDescriptor = {
    key: 'contacts.view',
    kind: 'quota',
    section: 'CONTACT',
    label: 'Contacts',
    period: 'SUBSCRIPTION',
  };

  it('describes values the way the plan page shows them', () => {
    expect(describeValue(quota, { limit: 5 })).toBe('5 per month');
    expect(describeValue(quota, { limit: null, fairUse: 300 })).toBe('Unlimited (fair use 300 per month)');
    expect(describeValue(contacts, { limit: 60, perMonths: 3 })).toBe('60 per 3 months');
    expect(
      describeValue({ key: 'b', kind: 'boolean', section: 'X', label: 'B' }, true),
    ).toBe('Yes');
  });

  it('compares values regardless of key order', () => {
    expect(sameValue({ limit: 5, perMonths: 3 }, { perMonths: 3, limit: 5 })).toBe(true);
    expect(sameValue({ limit: 5 }, { limit: 6 })).toBe(false);
  });
});

describe('agents', () => {
  it('labels statuses the way the agent program does (SUSPENDED is "paused")', async () => {
    const { agentStatusLabel } = await import('./agents');
    expect(agentStatusLabel('SUSPENDED')).toBe('paused');
    expect(agentStatusLabel('PENDING_APPROVAL')).toBe('awaiting approval');
  });

  it('offers approve and reject only for an application awaiting approval', async () => {
    const { canDecide, AGENT_STATUSES } = await import('./agents');
    expect(AGENT_STATUSES.filter(canDecide)).toEqual(['PENDING_APPROVAL']);
  });
});

describe('agent actions', () => {
  it('offers only moves the API allows', async () => {
    const { manageActions } = await import('./agents');
    expect(manageActions('ACTIVE')).toEqual(['pause', 'terminate', 'replaceCode']);
    expect(manageActions('SUSPENDED')).toEqual(['resume', 'terminate']);
    for (const status of ['PENDING_APPROVAL', 'REJECTED', 'TERMINATED'] as const) {
      expect(manageActions(status)).toEqual([]);
    }
  });
});

describe('money helpers', () => {
  it('offers commission actions only while they can still change', async () => {
    const { commissionActions } = await import('./money');
    expect(commissionActions('READY')).toEqual(['approve', 'cancel', 'override']);
    expect(commissionActions('APPROVED')).toEqual(['cancel', 'override']);
    for (const status of ['PAID', 'CANCELLED', 'REVERSED'] as const) {
      expect(commissionActions(status)).toEqual([]);
    }
  });

  it('works out payout periods in Indian time', async () => {
    const { periodOf, previousPeriod, PERIOD_PATTERN } = await import('./money');
    // 31 Oct 20:00 UTC is already 1 Nov in India.
    expect(periodOf(new Date('2026-10-31T20:00:00Z'))).toBe('2026-11');
    expect(previousPeriod(new Date('2026-10-31T20:00:00Z'))).toBe('2026-10');
    expect(previousPeriod(new Date('2027-01-15T10:00:00Z'))).toBe('2026-12');
    expect(PERIOD_PATTERN.test('2026-11')).toBe(true);
    expect(PERIOD_PATTERN.test('2026-13')).toBe(false);
  });

  it('shows basis points as a percentage', async () => {
    const { formatBps } = await import('./money');
    expect(formatBps(1000)).toBe('10%');
    expect(formatBps(550)).toBe('5.5%');
  });
});
