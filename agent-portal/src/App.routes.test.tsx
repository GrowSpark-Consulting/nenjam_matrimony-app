import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import type { ApiSetup } from './api';
import { ApiError } from './api/errors';
import { MockAgentApi } from './api/mockAgentApi';
import { SESSION_STORAGE_KEY, SessionStore } from './api/session';
import type { ReferralLink } from './api/types';
import { AppRoutes } from './App';
import { PortalProvider } from './state/PortalContext';

function setup(api?: (s: SessionStore) => MockAgentApi): ApiSetup & { api: MockAgentApi } {
  window.localStorage.clear();
  const sessions = new SessionStore(window.localStorage);
  return { api: api ? api(sessions) : new MockAgentApi(sessions), sessions, usingMocks: true };
}

/** Signs in through the API (as the sign-in screen would) before rendering. */
async function signedInAs(s: ApiSetup & { api: MockAgentApi }, phone: string) {
  const { challengeId } = await s.api.requestOtp(phone);
  s.sessions.set(await s.api.verifyOtp(challengeId, '123456'));
}

function renderAt(path: string, s: ApiSetup) {
  return render(
    <PortalProvider setup={s}>
      <MemoryRouter initialEntries={[path]}>
        <AppRoutes />
      </MemoryRouter>
    </PortalProvider>,
  );
}

describe('protected routes and agent-status restrictions', () => {
  it('signed out: every private route goes to sign-in', async () => {
    for (const path of ['/', '/referrals', '/earnings', '/payouts', '/payout-details', '/status']) {
      const { unmount } = renderAt(path, setup());
      expect(await screen.findByLabelText('Mobile number'), path).toBeInTheDocument();
      unmount();
    }
  });

  it('help is public', async () => {
    renderAt('/help', setup());
    expect(await screen.findByText('Help & Support')).toBeInTheDocument();
  });

  it('an applicant can only reach the application form', async () => {
    const s = setup();
    await signedInAs(s, '+919876543210');
    renderAt('/referrals', s);
    expect(await screen.findByText('Apply to become a partner')).toBeInTheDocument();
  });

  it('pending agent: no dashboard, referrals or payout details', async () => {
    const s = setup();
    await signedInAs(s, '+919000000001');
    for (const path of ['/', '/referrals', '/payout-details', '/earnings']) {
      const { unmount } = renderAt(path, s);
      expect(await screen.findByText("We're reviewing your application."), path).toBeInTheDocument();
      unmount();
    }
  });

  it('rejected agent sees the reason and NO "Apply again" (decision pending)', async () => {
    const s = setup();
    await signedInAs(s, '+919000000002');
    renderAt('/', s);
    expect(await screen.findByText(/Reason:/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /apply again/i })).toBeNull();
  });

  it('terminated agent: money pages only, no code or sharing', async () => {
    const s = setup();
    await signedInAs(s, '+919000000004');
    renderAt('/', s);
    expect(await screen.findByRole('heading', { name: 'Earnings' })).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Home' })).toBeNull();
    expect(screen.queryByRole('link', { name: 'People who joined' })).toBeNull();
  });

  it('paused agent cannot open payout details', async () => {
    const s = setup();
    await signedInAs(s, '+919000000003');
    renderAt('/payout-details', s);
    expect(await screen.findByText('Your referral code')).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Payout details' })).toBeNull();
  });
});

describe('sessions', () => {
  it('sign out clears the stored session and returns to sign-in', async () => {
    const s = setup();
    await signedInAs(s, '+919000000005');
    renderAt('/', s);
    await userEvent.click(await screen.findByRole('button', { name: 'Sign out' }));
    expect(await screen.findByLabelText('Mobile number')).toBeInTheDocument();
    expect(window.localStorage.getItem(SESSION_STORAGE_KEY)).toBeNull();
  });

  it('an expired applicant session goes back to OTP (it cannot be refreshed)', async () => {
    const s = setup();
    window.localStorage.setItem(
      SESSION_STORAGE_KEY,
      JSON.stringify({
        session: { scope: 'APPLICANT', accessToken: 'mock-applicant:+919876543210', expiresInSeconds: 900 },
        expiresAt: Date.now() - 1000,
      }),
    );
    renderAt('/apply', s);
    expect(await screen.findByLabelText('Mobile number')).toBeInTheDocument();
    expect(window.localStorage.getItem(SESSION_STORAGE_KEY)).toBeNull();
  });

  it('sign-in buttons stay disabled while a request is in flight (no duplicates)', async () => {
    const s = setup();
    let release: () => void = () => {};
    const request = vi
      .spyOn(s.api, 'requestOtp')
      .mockImplementation(
        () =>
          new Promise((resolve) => {
            release = () => resolve({ challengeId: 'c1', expiresInSeconds: 300, resendAfterSeconds: 30 });
          }),
      );
    renderAt('/sign-in', s);
    const user = userEvent.setup();
    await user.type(screen.getByLabelText('Mobile number'), '9000000005');
    const send = screen.getByRole('button', { name: 'Send code' });
    await user.click(send);
    expect(send).toBeDisabled();
    await user.click(send);
    expect(request).toHaveBeenCalledTimes(1);
    release();
    expect(await screen.findByLabelText('Code')).toBeInTheDocument();
  });
});

describe('loading, empty, error and retry states', () => {
  it('a failed load shows a calm message and Retry works', async () => {
    let fail = true;
    class Flaky extends MockAgentApi {
      async getReferralLinks(): Promise<ReferralLink[]> {
        if (fail) throw ApiError.network();
        return super.getReferralLinks();
      }
    }
    const s = setup((sessions) => new Flaky(sessions));
    await signedInAs(s, '+919000000005');
    renderAt('/', s);
    expect(await screen.findByText(/Couldn't reach Nenjam/)).toBeInTheDocument();
    fail = false;
    await userEvent.click(screen.getAllByRole('button', { name: 'Try again' })[0]);
    expect(await screen.findByLabelText('Referral code')).toHaveTextContent('NM7K2P9X');
  });

  it('server errors never show raw server text', async () => {
    class Broken extends MockAgentApi {
      async getReferralLinks(): Promise<ReferralLink[]> {
        throw new ApiError(500, 'TypeError: cannot read x at agent.service.ts:42');
      }
    }
    const s = setup((sessions) => new Broken(sessions));
    await signedInAs(s, '+919000000005');
    renderAt('/', s);
    expect(await screen.findByText(/having trouble/)).toBeInTheDocument();
    expect(screen.queryByText(/agent\.service\.ts/)).toBeNull();
  });

  it('empty lists say so instead of inventing data', async () => {
    const s = setup();
    await signedInAs(s, '+919000000005');
    renderAt('/payouts', s);
    expect(await screen.findByText('No payouts yet.')).toBeInTheDocument();
    renderAt('/earnings', s);
    expect(await screen.findByText('No commissions yet.')).toBeInTheDocument();
    expect(screen.getAllByText('₹0.00').length).toBeGreaterThan(0);
  });
});

describe('application refusals (contract)', () => {
  it('409 APPLICATION_EXISTS shows the server message and offers "Sign in again"', async () => {
    class Exists extends MockAgentApi {
      async apply(): Promise<never> {
        throw new ApiError(409, 'An application already exists for this phone.', {
          code: 'APPLICATION_EXISTS',
          agentStatus: 'PENDING_APPROVAL',
        });
      }
    }
    const s = setup((sessions) => new Exists(sessions));
    await signedInAs(s, '+919876543210');
    renderAt('/apply', s);
    const user = userEvent.setup();
    await user.type(await screen.findByLabelText('Full name'), 'Meena R');
    await user.type(screen.getByLabelText('City'), 'Coimbatore');
    await user.type(screen.getByLabelText('State'), 'Tamil Nadu');
    await user.click(screen.getByRole('button', { name: 'Submit application' }));
    expect(
      await screen.findByText('An application already exists for this phone.'),
    ).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Sign in again' }));
    await waitFor(() => expect(window.localStorage.getItem(SESSION_STORAGE_KEY)).toBeNull());
    expect(await screen.findByLabelText('Mobile number')).toBeInTheDocument();
  });

  it('PAN is validated before sending and upper-cased', async () => {
    const s = setup();
    const apply = vi.spyOn(s.api, 'apply');
    await signedInAs(s, '+919876543210');
    renderAt('/apply', s);
    const user = userEvent.setup();
    await user.type(await screen.findByLabelText('Full name'), 'Meena R');
    await user.type(screen.getByLabelText('City'), 'Coimbatore');
    await user.type(screen.getByLabelText('State'), 'Tamil Nadu');
    await user.type(screen.getByLabelText('PAN (optional)'), 'abcde12');
    expect(screen.getByText('PAN should look like ABCDE1234F.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Submit application' })).toBeDisabled();
    await user.type(screen.getByLabelText('PAN (optional)'), '34f');
    await user.click(screen.getByRole('button', { name: 'Submit application' }));
    await waitFor(() => expect(apply).toHaveBeenCalled());
    expect(apply.mock.calls[0][0]).toMatchObject({ pan: 'ABCDE1234F' });
  });
});
