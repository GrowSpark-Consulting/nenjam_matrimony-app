import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import type { ApiSetup } from './api';
import { MockAgentApi } from './api/mockAgentApi';
import { SessionStore } from './api/session';
import type { Balance, Commission, Page, ReferralLink } from './api/types';
import { AppRoutes } from './App';
import { PortalProvider } from './state/PortalContext';

/** Agent Home (GET /agent/referral-links + GET /agent/balance). Test data only. */

const ACTIVE = '+919000000005';

class HomeApi extends MockAgentApi {
  balance: () => Promise<Balance> = () => super.getBalance();
  commissions: () => Promise<Page<Commission>> = async () => ({ items: [], nextCursor: null });
  override getBalance(): Promise<Balance> {
    return this.balance();
  }
  override getCommissions(): Promise<Page<Commission>> {
    return this.commissions();
  }
}

async function renderAt(path: string, tweak: (api: HomeApi) => void = () => {}) {
  window.localStorage.clear();
  const sessions = new SessionStore(window.localStorage);
  const api = new HomeApi(sessions);
  tweak(api);
  const { challengeId } = await api.requestOtp(ACTIVE);
  sessions.set(await api.verifyOtp(challengeId, '123456'));
  const setup: ApiSetup = { api, sessions, usingMocks: true };
  const view = render(
    <PortalProvider setup={setup}>
      <MemoryRouter initialEntries={[path]}>
        <AppRoutes />
      </MemoryRouter>
    </PortalProvider>,
  );
  return { api, sessions, view };
}

describe('Agent Home balance', () => {
  it('shows a loading state, then the figures', async () => {
    let release!: (b: Balance) => void;
    await renderAt('/', (a) => {
      a.balance = () => new Promise<Balance>((r) => (release = r));
    });
    expect(await screen.findByText('Loading your balance…')).toBeInTheDocument();
    release({
      onHoldPaise: 0,
      availablePaise: 150050,
      paidPaise: 700000,
      minPayoutPaise: 50000,
      canRequestPayout: true,
    });
    expect(await screen.findByText('₹1,500.50')).toBeInTheDocument();
    expect(screen.getByText('₹7,000.00')).toBeInTheDocument();
    expect(screen.queryByText('Loading your balance…')).toBeNull();
  });

  it('zero balance is shown as zeros, not as an error or "coming soon"', async () => {
    await renderAt('/');
    await waitFor(() => expect(screen.getAllByText('₹0.00')).toHaveLength(3));
    expect(screen.queryByRole('alert')).toBeNull();
    expect(screen.queryByText('Balance coming soon')).toBeNull();
    // The code card is there alongside.
    expect(screen.getByLabelText('Referral code')).toHaveTextContent('NM7K2P9X');
  });
});

describe('no white screen on an unexpected response', () => {
  // Regression: responses are typed but not validated at runtime, and a
  // commission without `rate` threw inside EarningsPage, which unmounted the
  // whole portal (an empty <div /> in the body).
  it('a commission missing its rate shows a message and keeps the navigation', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {}); // React logs the caught error
    const bad = { id: 'c1', status: 'ON_HOLD', amountPaise: 100 } as unknown as Commission;
    await renderAt('/earnings', (a) => {
      a.commissions = async () => ({ items: [bad], nextCursor: null });
    });
    expect(await screen.findByText('Something went wrong showing this page.')).toBeInTheDocument();
    expect(screen.getByRole('navigation', { name: 'Main' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Reload' })).toBeInTheDocument();
    // The failed page's data is not shown, and no error text leaks.
    expect(document.body).not.toHaveTextContent(/TypeError|undefined|Cannot read/);
  });

  it('leaving the failed page recovers: another page renders normally', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const bad = { id: 'c1', status: 'ON_HOLD', amountPaise: 100 } as unknown as Commission;
    await renderAt('/earnings', (a) => {
      a.commissions = async () => ({ items: [bad], nextCursor: null });
    });
    await screen.findByText('Something went wrong showing this page.');
    const user = userEvent.setup();
    await user.click(screen.getByRole('link', { name: 'Payouts' }));
    expect(await screen.findByText('No payouts yet.')).toBeInTheDocument();
    expect(screen.queryByText('Something went wrong showing this page.')).toBeNull();
  });
});

describe('Agent Home share section states', () => {
  it('shows a loading state, then the link and QR from the backend', async () => {
    let release!: (l: ReferralLink[]) => void;
    await renderAt('/', (a) => {
      a.getReferralLinks = () => new Promise<ReferralLink[]>((r) => (release = r));
    });
    expect((await screen.findAllByText('Loading…')).length).toBeGreaterThan(0);
    await waitFor(() => expect(release).toBeTypeOf('function'));
    release([
      {
        codeId: 'c1',
        code: 'NM7K2P9X',
        isPrimary: true,
        link: 'https://example.test/?ref=NM7K2P9X',
        qrPayload: 'https://example.test/?ref=NM7K2P9X',
        shareMessages: [],
        shareable: true,
      },
    ]);
    expect(await screen.findByLabelText('Share link')).toHaveTextContent('https://example.test/?ref=NM7K2P9X');
    expect(screen.getByRole('button', { name: 'Download QR' })).toBeInTheDocument();
  });

  it('an API error shows a message with Try again, which reloads', async () => {
    const user = userEvent.setup();
    let fail = true;
    const { api } = await renderAt('/', (a) => {
      const real = a.getReferralLinks.bind(a);
      a.getReferralLinks = async () => {
        if (fail) throw new Error('down');
        return real();
      };
    });
    const retry = await screen.findByRole('button', { name: /try again/i });
    fail = false;
    await user.click(retry);
    expect(await screen.findByLabelText('Referral code')).toHaveTextContent('NM7K2P9X');
    expect(api).toBeDefined();
  });
});
