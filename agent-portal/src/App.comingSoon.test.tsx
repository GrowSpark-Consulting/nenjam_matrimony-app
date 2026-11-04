import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import type { ApiSetup } from './api';
import { ApiError, isRouteNotDeployed } from './api/errors';
import { MockAgentApi } from './api/mockAgentApi';
import { SessionStore } from './api/session';
import type { Balance, Commission, Page, Payout, PayoutDetailsInput, PayoutDetailsSummary } from './api/types';
import { AppRoutes } from './App';
import { ComingSoonState, FormField, StatusBadge, SummaryCard } from './components/ui';
import { PortalProvider } from './state/PortalContext';

const ACTIVE = '+919000000005';
const missing = () => new ApiError(404, 'Cannot GET /agent/x', { code: null });
const outage = () => new ApiError(500, 'boom', { code: null });

/** A mock whose money routes can be made missing (404, no code) or broken. */
class MoneyApi extends MockAgentApi {
  balanceError: ApiError | null = null;
  commissionsError: ApiError | null = null;
  payoutsError: ApiError | null = null;
  patchError: ApiError | null = null;
  balanceCalls = 0;
  override getBalance(): Promise<Balance> {
    this.balanceCalls += 1;
    return this.balanceError ? Promise.reject(this.balanceError) : super.getBalance();
  }
  override getCommissions(q: Parameters<MockAgentApi['getCommissions']>[0]): Promise<Page<Commission>> {
    return this.commissionsError ? Promise.reject(this.commissionsError) : super.getCommissions(q);
  }
  override getPayouts(q: Parameters<MockAgentApi['getPayouts']>[0]): Promise<Page<Payout>> {
    return this.payoutsError ? Promise.reject(this.payoutsError) : super.getPayouts(q);
  }
  override updatePayoutDetails(b: PayoutDetailsInput): Promise<PayoutDetailsSummary> {
    return this.patchError ? Promise.reject(this.patchError) : super.updatePayoutDetails(b);
  }
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

describe('isRouteNotDeployed', () => {
  it('is true only for a 404 without a code', () => {
    expect(isRouteNotDeployed(missing())).toBe(true);
    expect(isRouteNotDeployed(new ApiError(404, 'x', { code: 'AGENT_NOT_FOUND' }))).toBe(false);
    expect(isRouteNotDeployed(outage())).toBe(false);
    expect(isRouteNotDeployed(new Error('x'))).toBe(false);
  });
});

describe('endpoints that are not deployed show "coming soon", never fake figures', () => {
  it('home: balance coming soon, referral code still works', async () => {
    await renderAt('/', (a) => (a.balanceError = missing()));
    expect(await screen.findByText('Balance coming soon')).toBeInTheDocument();
    expect(screen.getByLabelText('Referral code')).toHaveTextContent('NM7K2P9X');
    expect(screen.queryByText(/₹/)).toBeNull();
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('earnings: one coming-soon state when both routes are missing', async () => {
    await renderAt('/earnings', (a) => {
      a.balanceError = missing();
      a.commissionsError = missing();
    });
    expect(await screen.findByText('Earnings coming soon')).toBeInTheDocument();
    expect(screen.getByText('Your balance will be available here soon.')).toBeInTheDocument();
    expect(screen.getByText('Your commissions list will be available here soon.')).toBeInTheDocument();
    expect(screen.queryByText(/₹/)).toBeNull();
    expect(screen.queryByText(/partner program isn't available/)).toBeNull();
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('payouts: coming soon, no records', async () => {
    await renderAt('/payouts', (a) => (a.payoutsError = missing()));
    expect(await screen.findByText('Payouts coming soon')).toBeInTheDocument();
    expect(screen.queryByText('No payouts yet.')).toBeNull();
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('a real 500 stays a retryable error, not coming soon', async () => {
    const api = await renderAt('/payouts', (a) => (a.payoutsError = outage()));
    expect(await screen.findByRole('alert')).toHaveTextContent('having trouble');
    expect(screen.queryByText('Payouts coming soon')).toBeNull();
    api.payoutsError = null;
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }));
    expect(await screen.findByText('No payouts yet.')).toBeInTheDocument();
  });

  it('home: a balance outage retries only the balance call', async () => {
    const api = await renderAt('/', (a) => (a.balanceError = outage()));
    await screen.findByRole('alert');
    expect(screen.getByLabelText('Referral code')).toBeInTheDocument();
    const before = api.balanceCalls;
    api.balanceError = null;
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }));
    expect(await screen.findByText('On hold')).toBeInTheDocument();
    expect(api.balanceCalls).toBe(before + 1);
  });
});

describe('failures stay recoverable and never invent data', () => {
  it('a 503 on balance keeps the code and the Active status visible, then retry recovers', async () => {
    const api = await renderAt('/', (a) => (a.balanceError = new ApiError(503, 'x', { code: null })));
    expect(await screen.findByRole('alert')).toHaveTextContent('having trouble');
    expect(screen.getByLabelText('Referral code')).toHaveTextContent('NM7K2P9X');
    expect(screen.getAllByText('Active').length).toBeGreaterThan(0);
    expect(screen.queryByText(/₹/)).toBeNull();
    api.balanceError = null;
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }));
    expect(await screen.findByText('On hold')).toBeInTheDocument();
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('a network failure on commissions is an error with retry, not coming soon', async () => {
    const api = await renderAt('/earnings', (a) => (a.commissionsError = ApiError.network()));
    expect(await screen.findByRole('alert')).toHaveTextContent("Couldn't reach Nenjam");
    expect(screen.queryByText(/coming soon/i)).toBeNull();
    api.commissionsError = null;
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }));
    expect(await screen.findByText('No commissions yet.')).toBeInTheDocument();
  });

  it('a documented 404 that carries a code is not treated as "not deployed"', async () => {
    await renderAt('/payouts', (a) => {
      a.payoutsError = new ApiError(404, 'No such payout.', { code: 'PAYOUT_NOT_FOUND' });
    });
    expect(await screen.findByRole('alert')).toHaveTextContent('No such payout.');
    expect(screen.queryByText('Payouts coming soon')).toBeNull();
  });
});

describe('payout details', () => {
  async function fillUpi(value: string) {
    await userEvent.type(await screen.findByLabelText('UPI ID'), value);
  }

  it('shows an unavailable state, not "saved", when the route is missing', async () => {
    await renderAt('/payout-details', (a) => (a.patchError = missing()));
    await fillUpi('ravi@okbank');
    await userEvent.click(screen.getByRole('button', { name: 'Save' }));
    expect(await screen.findByText('Payout details coming soon')).toBeInTheDocument();
    expect(screen.queryByText(/Saved:/)).toBeNull();
  });

  it('a failed save keeps the entered value and reports no success', async () => {
    await renderAt('/payout-details', (a) => (a.patchError = outage()));
    await fillUpi('ravi@okbank');
    await userEvent.click(screen.getByRole('button', { name: 'Save' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('having trouble');
    expect(screen.getByLabelText('UPI ID')).toHaveValue('ravi@okbank');
    expect(screen.queryByText(/Saved:/)).toBeNull();
  });

  it('validates inline, cancels edits, and clears fields after a real save', async () => {
    await renderAt('/payout-details');
    await fillUpi('nope');
    expect(await screen.findByText('Enter a UPI ID like name@bank.')).toBeInTheDocument();
    expect(screen.getByLabelText('UPI ID')).toHaveAttribute('aria-invalid', 'true');
    expect(screen.getByText('You have changes that are not saved yet.')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(screen.getByLabelText('UPI ID')).toHaveValue('');
    await fillUpi('ravi@okbank');
    await userEvent.click(screen.getByRole('button', { name: 'Save' }));
    expect(await screen.findByText(/^Saved:/)).toBeInTheDocument();
    await waitFor(() => expect(screen.getByLabelText('UPI ID')).toHaveValue(''));
  });
});

describe('copy feedback', () => {
  it('says so when the clipboard is unavailable', async () => {
    await renderAt('/');
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText: () => Promise.reject(new Error('denied')) },
    });
    await userEvent.click(await screen.findByRole('button', { name: 'Copy code' }));
    expect(await screen.findByText(/Couldn't copy/)).toBeInTheDocument();
  });

  it('confirms a successful copy', async () => {
    await renderAt('/');
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText } });
    await userEvent.click(await screen.findByRole('button', { name: 'Copy code' }));
    expect(writeText).toHaveBeenCalledWith('NM7K2P9X');
    expect(await screen.findByText('Copied to your clipboard.')).toBeInTheDocument();
  });
});

describe('shared components', () => {
  it('StatusBadge carries its meaning in text', () => {
    render(<StatusBadge tone="success">Active</StatusBadge>);
    expect(screen.getByText('Active')).toHaveClass('tone-success');
  });

  it('SummaryCard renders label, value and hint', () => {
    render(<SummaryCard label="Paid" value="₹1.00" hint="Already paid" />);
    expect(screen.getByText('Paid')).toBeInTheDocument();
    expect(screen.getByText('₹1.00')).toBeInTheDocument();
    expect(screen.getByText('Already paid')).toBeInTheDocument();
  });

  it('ComingSoonState is a labelled region', () => {
    render(<ComingSoonState title="Soon">Later.</ComingSoonState>);
    expect(screen.getByRole('region', { name: 'Soon' })).toHaveTextContent('Later.');
  });

  it('FormField wires label, hint and error to the control', () => {
    render(
      <FormField id="x" label="Thing" hint="A hint" error="Bad">
        {(p) => <input {...p} />}
      </FormField>,
    );
    const input = screen.getByLabelText('Thing');
    expect(input).toHaveAttribute('aria-invalid', 'true');
    expect(input).toHaveAccessibleDescription('A hint Bad');
  });
});
