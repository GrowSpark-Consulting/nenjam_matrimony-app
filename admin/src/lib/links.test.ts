import { describe, expect, it } from 'vitest';
import {
  agentsHref,
  readFilter,
  SUBSCRIPTION_PLANS,
  SUBSCRIPTION_STATUSES,
  subscriptionsHref,
  USER_STATUSES,
  usersHref,
} from './links';

describe('overview links', () => {
  it('opens list pages already filtered', () => {
    expect(subscriptionsHref({ status: 'ACTIVE', plan: 'PLATINUM' })).toBe(
      '/subscriptions/?status=ACTIVE&plan=PLATINUM',
    );
    expect(subscriptionsHref()).toBe('/subscriptions/');
    expect(agentsHref('PENDING_APPROVAL')).toBe('/agents/?status=PENDING_APPROVAL');
    expect(agentsHref()).toBe('/agents/');
    expect(usersHref({ status: 'BLOCKED' })).toBe('/users/?status=BLOCKED');
    expect(usersHref()).toBe('/users/');
  });

  it('reads back only known filter values', () => {
    const params = new URLSearchParams('status=ACTIVE&plan=platinum');
    expect(readFilter(params, 'status', SUBSCRIPTION_STATUSES)).toBe('ACTIVE');
    expect(readFilter(params, 'status', USER_STATUSES)).toBe('ACTIVE');
    // Case matters: an unknown value falls back to the page default.
    expect(readFilter(params, 'plan', SUBSCRIPTION_PLANS)).toBe('');
    expect(readFilter(params, 'missing', ['A'], 'A')).toBe('A');
    expect(readFilter(null, 'status', SUBSCRIPTION_STATUSES, 'X')).toBe('X');
  });

  it('round-trips what the overview links to', () => {
    const href = subscriptionsHref({ status: 'ACTIVE', plan: 'GOLD' });
    const params = new URLSearchParams(href.split('?')[1]);
    expect(readFilter(params, 'status', SUBSCRIPTION_STATUSES)).toBe('ACTIVE');
    expect(readFilter(params, 'plan', SUBSCRIPTION_PLANS)).toBe('GOLD');
  });
});
