import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import type { ApiSetup } from './api';
import type { PageQuery } from './api/agentApi';
import { HttpAgentApi } from './api/agentApi';
import { ApiError } from './api/errors';
import { HttpClient } from './api/http';
import { MockAgentApi } from './api/mockAgentApi';
import { SessionStore } from './api/session';
import type { Balance, Commission, CommissionStatus, Page, Payout } from './api/types';
import { AppRoutes } from './App';
import { PortalProvider } from './state/PortalContext';

/**
 * Regression tests for the agent money screens (Earnings, Payouts) against
 * contract-shaped responses: GET /agent/balance, /agent/commissions and
 * /agent/payouts (backend AgentBalance / AgentCommissionView /
 * AgentPayoutView). These fixtures are test data only — the shipped mock
 * returns no commissions or payouts.
 */

const ACTIVE = '+919000000005';

const commission = (over: Partial<Commission> = {}): Commission => ({
  id: 'com-1',
  referralId: 'ref-1',
  referralDisplayName: 'Priya S.',
  planName: 'Gold 3 months',
  basePaise: 99900,
  amountPaise: 9990,
  rate: { calcType: 'PERCENTAGE', value: 1000 },
  status: 'ON_HOLD',
  earnedOn: '2026-10-01',
  holdEndsOn: '2026-10-15',
  approvedOn: null,
  paidOn: null,
  ...over,
});

const payout = (over: Partial<Payout> = {}): Payout => ({
  id: 'pay-1',
  amountPaise: 150000,
  status: 'CREATED',
  reference: null,
  createdOn: '2026-10-20',
  paidOn: null,
  commissionCount: 3,
  ...over,
});

type CommissionQuery = PageQuery & { status?: CommissionStatus };

/** The shipped mock (sign-in, /me, /config) with scripted money routes. */
class MoneyApi extends MockAgentApi {
  balance: () => Promise<Balance> = () => super.getBalance();
  commissionPages: Record<string, Page<Commission> | ApiError> = {
    first: { items: [], nextCursor: null },
  };
  payoutPages: Record<string, Page<Payout> | ApiError> = {
    first: { items: [], nextCursor: null },
  };
  commissionQueries: CommissionQuery[] = [];
  payoutQueries: PageQuery[] = [];

  override getBalance(): Promise<Balance> {
    return this.balance();
  }

  override async getCommissions(query: CommissionQuery): Promise<Page<Commission>> {
    this.commissionQueries.push(query);
    return pageFor(this.commissionPages, query.cursor);
  }

  override async getPayouts(query: PageQuery): Promise<Page<Payout>> {
    this.payoutQueries.push(query);
    return pageFor(this.payoutPages, query.cursor);
  }
}

function pageFor<T>(pages: Record<string, Page<T> | ApiError>, cursor?: string | null): Page<T> {
  const page = pages[cursor ?? 'first'];
  if (!page) throw new Error(`unexpected cursor ${String(cursor)}`);
  if (page instanceof ApiError) {
    // One failure, then the next call for the same cursor succeeds.
    delete pages[cursor ?? 'first'];
    throw page;
  }
  return page;
}

async function renderAt(path: string, tweak: (api: MoneyApi) => void = () => {}) {
  window.localStorage.clear();
  const sessions = new SessionStore(window.localStorage);
  const api = new MoneyApi(sessions);
  tweak(api);
  const { challengeId } = await api.requestOtp(ACTIVE);
  sessions.set(await api.verifyOtp(challengeId, '123456'));
  const setup: ApiSetup = { api, sessions, usingMocks: true };
  render(
    <PortalProvider setup={setup}>
      <MemoryRouter initialEntries={[path]}>
        <AppRoutes />
      </MemoryRouter>
    </PortalProvider>,
  );
  return api;
}

const cards = () => screen.queryAllByRole('listitem').filter((li) => li.classList.contains('data-card'));

describe('Earnings: balance and commissions from the API', () => {
  it('shows every balance figure from GET /agent/balance, converted from paise', async () => {
    await renderAt('/earnings', (a) => {
      a.balance = async () => ({
        onHoldPaise: 9990,
        availablePaise: 123456,
        paidPaise: 500000,
        minPayoutPaise: 50000,
        canRequestPayout: true,
      });
    });
    expect(await screen.findByText('₹99.90')).toBeInTheDocument();
    expect(screen.getByText('₹1,234.56')).toBeInTheDocument();
    expect(screen.getByText('₹5,000.00')).toBeInTheDocument();
    expect(screen.getByText('Minimum payout')).toBeInTheDocument();
    expect(screen.getByText('₹500.00')).toBeInTheDocument();
    // Agents cannot create payouts, whatever canRequestPayout says.
    expect(screen.queryByRole('button', { name: /request/i })).toBeNull();
  });

  it('maps each commission field and labels the status from /agent/config', async () => {
    await renderAt('/earnings', (a) => {
      a.commissionPages = {
        first: {
          items: [
            commission(),
            commission({
              id: 'com-2',
              referralDisplayName: 'Karthik R.',
              status: 'PAID',
              holdEndsOn: null,
              approvedOn: '2026-09-20',
              paidOn: '2026-10-05',
              amountPaise: 25000,
              basePaise: 250000,
              rate: { calcType: 'PERCENTAGE', value: 1000 },
            }),
          ],
          nextCursor: null,
        },
      };
    });
    await waitFor(() => expect(cards()).toHaveLength(2));
    const [onHold, paid] = cards();

    const first = within(onHold);
    expect(first.getByText('₹99.90')).toBeInTheDocument();
    expect(first.getByText('On hold')).toBeInTheDocument();
    expect(first.getByText('Priya S.')).toBeInTheDocument();
    expect(first.getByText('Gold 3 months')).toBeInTheDocument();
    expect(first.getByText('10% of ₹999.00')).toBeInTheDocument();
    expect(first.getByText('2026-10-01')).toBeInTheDocument();
    expect(first.getByText('2026-10-15')).toBeInTheDocument();
    expect(first.queryByText('Paid')).toBeNull();

    const second = within(paid);
    expect(second.getByText('₹250.00')).toBeInTheDocument();
    expect(second.getByText('10% of ₹2,500.00')).toBeInTheDocument();
    expect(second.getAllByText('Paid')).toHaveLength(2); // badge + "Paid" date label
    expect(second.getByText('2026-10-05')).toBeInTheDocument();
    expect(second.queryByText('On hold until')).toBeNull();

    expect(screen.queryByText('No commissions yet.')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Load more' })).toBeNull();
  });

  it('empty list: the empty state, zero balance, no load more', async () => {
    const api = await renderAt('/earnings');
    expect(await screen.findByText('No commissions yet.')).toBeInTheDocument();
    expect(screen.getAllByText('₹0.00')).toHaveLength(3);
    expect(screen.queryByRole('button', { name: 'Load more' })).toBeNull();
    expect(api.commissionQueries).toEqual([{ cursor: null }]);
  });

  it('pagination: passes nextCursor back unchanged and appends the next page', async () => {
    const user = userEvent.setup();
    const api = await renderAt('/earnings', (a) => {
      a.commissionPages = {
        first: { items: [commission()], nextCursor: 'opaque/cursor==2' },
        'opaque/cursor==2': {
          items: [commission({ id: 'com-2', referralDisplayName: 'Karthik R.' })],
          nextCursor: null,
        },
      };
    });
    await waitFor(() => expect(cards()).toHaveLength(1));
    await user.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => expect(cards()).toHaveLength(2));
    expect(screen.getByText('Priya S.')).toBeInTheDocument();
    expect(screen.getByText('Karthik R.')).toBeInTheDocument();
    expect(api.commissionQueries).toEqual([{ cursor: null }, { cursor: 'opaque/cursor==2' }]);
    expect(screen.queryByRole('button', { name: 'Load more' })).toBeNull();
    expect(screen.queryByText('No commissions yet.')).toBeNull();
  });

  it('a failed "load more" keeps the loaded items and retries the same cursor', async () => {
    const user = userEvent.setup();
    const api = await renderAt('/earnings', (a) => {
      a.commissionPages = {
        first: { items: [commission()], nextCursor: 'c2' },
        c2: new ApiError(500, 'boom', { code: null }),
      };
    });
    await waitFor(() => expect(cards()).toHaveLength(1));
    await user.click(screen.getByRole('button', { name: 'Load more' }));
    expect(await screen.findByRole('alert')).toBeInTheDocument();
    expect(cards()).toHaveLength(1);
    expect(screen.queryByText('No commissions yet.')).toBeNull();

    api.commissionPages.c2 = {
      items: [commission({ id: 'com-2', referralDisplayName: 'Karthik R.' })],
      nextCursor: null,
    };
    await user.click(screen.getByRole('button', { name: 'Try again' }));
    await waitFor(() => expect(cards()).toHaveLength(2));
    expect(screen.queryByRole('alert')).toBeNull();
    expect(api.commissionQueries.map((q) => q.cursor)).toEqual([null, 'c2', 'c2']);
  });
});

describe('Payouts: read-only history from the API', () => {
  it('CREATED shows as "Processing"; reference and paid date only when present', async () => {
    await renderAt('/payouts', (a) => {
      a.payoutPages = {
        first: {
          items: [
            payout(),
            payout({
              id: 'pay-2',
              amountPaise: 75050,
              status: 'PAID',
              reference: 'UTR123456789',
              paidOn: '2026-10-25',
              commissionCount: 1,
            }),
          ],
          nextCursor: null,
        },
      };
    });
    await waitFor(() => expect(cards()).toHaveLength(2));
    const [created, paid] = cards().map((c) => within(c));

    expect(created.getByText('₹1,500.00')).toBeInTheDocument();
    expect(created.getByText('Processing')).toBeInTheDocument();
    expect(created.queryByText('CREATED')).toBeNull();
    expect(created.getByText('3')).toBeInTheDocument();
    expect(created.getByText('2026-10-20')).toBeInTheDocument();
    expect(created.queryByText('Reference')).toBeNull();
    expect(created.queryByText('Paid')).toBeNull();

    expect(paid.getByText('₹750.50')).toBeInTheDocument();
    expect(paid.getByText('UTR123456789')).toBeInTheDocument();
    expect(paid.getByText('2026-10-25')).toBeInTheDocument();
  });

  it('empty list: the empty state and no load more', async () => {
    await renderAt('/payouts');
    expect(await screen.findByText('No payouts yet.')).toBeInTheDocument();
    expect(cards()).toHaveLength(0);
    expect(screen.queryByRole('button', { name: 'Load more' })).toBeNull();
  });

  it('pagination: second page appended with the server cursor', async () => {
    const user = userEvent.setup();
    const api = await renderAt('/payouts', (a) => {
      a.payoutPages = {
        first: { items: [payout()], nextCursor: 'p2' },
        p2: { items: [payout({ id: 'pay-2', amountPaise: 20000 })], nextCursor: null },
      };
    });
    await waitFor(() => expect(cards()).toHaveLength(1));
    await user.click(screen.getByRole('button', { name: 'Load more' }));
    await waitFor(() => expect(cards()).toHaveLength(2));
    expect(screen.getByText('₹200.00')).toBeInTheDocument();
    expect(api.payoutQueries).toEqual([{ cursor: null }, { cursor: 'p2' }]);
  });
});

describe('HttpAgentApi money routes (request mapping)', () => {
  function client(body: unknown) {
    const store = new Map<string, string>();
    const storage = {
      getItem: (k: string) => store.get(k) ?? null,
      setItem: (k: string, v: string) => void store.set(k, v),
      removeItem: (k: string) => void store.delete(k),
      clear: () => store.clear(),
      key: () => null,
      length: 0,
    } as Storage;
    const sessions = new SessionStore(storage);
    sessions.set({
      scope: 'AGENT',
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      expiresInSeconds: 900,
      agent: {} as never,
    });
    const fetchFn = vi.fn(async (..._args: [string, RequestInit]) =>
      new Response(JSON.stringify(body), { status: 200 }),
    );
    const api = new HttpAgentApi(
      new HttpClient('https://api.test', sessions, fetchFn as unknown as typeof fetch, null),
    );
    return { api, fetchFn };
  }

  it('GET /agent/commissions: first page sends no cursor; later pages send it verbatim', async () => {
    const page = { items: [commission()], nextCursor: 'x/y==' };
    const { api, fetchFn } = client(page);
    await expect(api.getCommissions({ cursor: null })).resolves.toEqual(page);
    await api.getCommissions({ cursor: 'x/y==', status: 'PAID' });
    const [first, second] = fetchFn.mock.calls;
    expect(first[0]).toBe('https://api.test/agent/commissions');
    expect(first[1].method).toBe('GET');
    expect(first[1].headers).toMatchObject({
      'Accept-Version': '1',
      Authorization: 'Bearer access-1',
    });
    const url = new URL(second[0]);
    expect(url.pathname).toBe('/agent/commissions');
    expect(url.searchParams.get('cursor')).toBe('x/y==');
    expect(url.searchParams.get('status')).toBe('PAID');
  });

  it('GET /agent/balance returns the body unchanged', async () => {
    const balance: Balance = {
      onHoldPaise: 1,
      availablePaise: 2,
      paidPaise: 3,
      minPayoutPaise: 50000,
      canRequestPayout: false,
    };
    const { api, fetchFn } = client(balance);
    await expect(api.getBalance()).resolves.toEqual(balance);
    expect(fetchFn.mock.calls[0][0]).toBe('https://api.test/agent/balance');
  });

  it('GET /agent/payouts with a cursor; no body, never a write', async () => {
    const { api, fetchFn } = client({ items: [], nextCursor: null });
    await api.getPayouts({ cursor: 'p2' });
    const [url, init] = fetchFn.mock.calls[0];
    expect(url).toBe('https://api.test/agent/payouts?cursor=p2');
    expect(init.method).toBe('GET');
    expect(init.body).toBeUndefined();
  });
});
