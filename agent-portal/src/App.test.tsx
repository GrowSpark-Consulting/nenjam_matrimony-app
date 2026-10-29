import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import type { ApiSetup } from './api';
import { MockAgentApi } from './api/mockAgentApi';
import { SessionStore } from './api/session';
import { AppRoutes } from './App';
import { SUPPORT_CONTACT_PLACEHOLDER } from './lib/helpContent';
import { PortalProvider } from './state/PortalContext';

function setup(): ApiSetup & { api: MockAgentApi } {
  window.localStorage.clear();
  const sessions = new SessionStore(window.localStorage);
  return { api: new MockAgentApi(sessions), sessions, usingMocks: true };
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

async function signIn(phone: string) {
  const user = userEvent.setup();
  await user.type(await screen.findByLabelText('Mobile number'), phone);
  await user.click(screen.getByRole('button', { name: 'Send code' }));
  await user.type(await screen.findByLabelText('Code'), '123456');
  await user.click(screen.getByRole('button', { name: 'Verify' }));
  return user;
}

describe('Agent Portal flows (mock API)', () => {
  it('sign-in sends the challengeId from the request with the code', async () => {
    const s = setup();
    const request = vi.spyOn(s.api, 'requestOtp');
    const verify = vi.spyOn(s.api, 'verifyOtp');
    renderAt('/sign-in', s);
    await signIn('90000 00005');
    await waitFor(() => expect(verify).toHaveBeenCalled());
    const { challengeId } = await request.mock.results[0].value;
    expect(request).toHaveBeenCalledWith('+919000000005');
    expect(verify).toHaveBeenCalledWith(challengeId, '123456');
  });

  it('an applicant applies and lands on Pending with no second OTP', async () => {
    const s = setup();
    const request = vi.spyOn(s.api, 'requestOtp');
    renderAt('/sign-in', s);
    const user = await signIn('98765 43210');
    await user.type(await screen.findByLabelText('Full name'), 'Meena R');
    await user.type(screen.getByLabelText('City'), 'Coimbatore');
    await user.type(screen.getByLabelText('State'), 'Tamil Nadu');
    expect(screen.getByText(/PAN is optional now/)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Submit application' }));
    expect(await screen.findByText("We're reviewing your application.")).toBeInTheDocument();
    expect(request).toHaveBeenCalledTimes(1);
    expect(s.sessions.get()?.session.scope).toBe('AGENT');
  });

  it('home shows the backend share messages as returned, hides a null link/QR', async () => {
    const s = setup();
    renderAt('/sign-in', s);
    await signIn('90000 00005');
    expect(await screen.findByLabelText('Referral code')).toHaveTextContent('NM7K2P9X');
    const links = await s.api.getReferralLinks();
    const { en, ta } = links[0].shareMessages[0].text;
    // Rendered exactly as the API returned it (the approved wording, no link line).
    expect(en).toBe(
      "Hi! I'm Ravi Kumar. Join Nenjam, a trusted matrimony app, and use my referral code NM7K2P9X when you sign up to get 5% off your first plan.",
    );
    expect(
      screen.getByText((_, el) => el?.classList.contains('message') === true && el.textContent === en),
    ).toBeInTheDocument();
    expect(
      screen.getByText((_, el) => el?.classList.contains('message') === true && el.textContent === ta),
    ).toBeInTheDocument();
    const wa = screen.getAllByRole('link', { name: 'Share on WhatsApp' });
    expect(wa[0]).toHaveAttribute('href', `https://wa.me/?text=${encodeURIComponent(en)}`);
    expect(document.querySelector('.qr')).toBeNull();
  });

  it('a paused agent cannot share', async () => {
    const s = setup();
    renderAt('/sign-in', s);
    await signIn('90000 00003');
    expect(await screen.findByText(/Sharing is turned off/)).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Share on WhatsApp' })).toBeNull();
    for (const b of screen.getAllByRole('button', { name: 'Share on WhatsApp' })) {
      expect(b).toBeDisabled();
    }
  });

  it('a pending agent sees the status screen, not the dashboard', async () => {
    const s = setup();
    renderAt('/sign-in', s);
    await signIn('90000 00001');
    expect(await screen.findByText("We're reviewing your application.")).toBeInTheDocument();
    expect(screen.queryByText('Your referral code')).toBeNull();
  });

  it('help shows the approved text with the contact still a placeholder', async () => {
    renderAt('/help', setup());
    expect(await screen.findByText('Help & Support')).toBeInTheDocument();
    expect(
      screen.getByText(`Contact the Nenjam team at ${SUPPORT_CONTACT_PLACEHOLDER}.`),
    ).toBeInTheDocument();
  });
});
