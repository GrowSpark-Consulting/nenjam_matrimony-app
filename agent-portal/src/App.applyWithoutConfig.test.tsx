import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import type { ApiSetup } from './api';
import { ApiError } from './api/errors';
import { MockAgentApi } from './api/mockAgentApi';
import { SessionStore } from './api/session';
import type { AgentConfig, AgentSession, ApplicationInput } from './api/types';
import { AppRoutes } from './App';
import { PortalProvider } from './state/PortalContext';

/**
 * Applying must not depend on GET /agent/config. The backend only lets an
 * AGENT-scope token read it (agent-http.ts: default scope AGENT), so an
 * applicant could never load it before applying — the form has to work
 * without it, and a failing config after approval must not undo the apply.
 */

/** In-browser mock (test only); /agent/config always fails. */
class NoConfigApi extends MockAgentApi {
  calls: string[] = [];
  configError: ApiError = new ApiError(503, 'unavailable', { code: 'AGENT_PROGRAM_UNAVAILABLE' });

  override getConfig(): Promise<AgentConfig> {
    this.calls.push('config');
    return Promise.reject(this.configError);
  }

  override async apply(input: ApplicationInput): Promise<AgentSession> {
    this.calls.push('apply');
    return super.apply(input);
  }
}

async function applicant(configError?: ApiError) {
  window.localStorage.clear();
  const sessions = new SessionStore(window.localStorage);
  const api = new NoConfigApi(sessions);
  if (configError) api.configError = configError;
  const { challengeId } = await api.requestOtp('+919876543210'); // no agent record
  sessions.set(await api.verifyOtp(challengeId, '123456'));
  expect(sessions.get()?.session.scope).toBe('APPLICANT');
  const setup: ApiSetup = { api, sessions, usingMocks: true };
  render(
    <PortalProvider setup={setup}>
      <MemoryRouter initialEntries={['/']}>
        <AppRoutes />
      </MemoryRouter>
    </PortalProvider>,
  );
  return { api, sessions };
}

async function fillAndSubmit() {
  const user = userEvent.setup();
  await user.type(await screen.findByLabelText('Full name'), 'Meena R');
  await user.type(screen.getByLabelText('City'), 'Coimbatore');
  await user.type(screen.getByLabelText('State'), 'Tamil Nadu');
  await user.click(screen.getByRole('button', { name: 'Submit application' }));
}

describe('applying without /agent/config', () => {
  it('an applicant never calls /agent/config before submitting', async () => {
    const { api } = await applicant();
    expect(await screen.findByText('Apply to become a partner')).toBeInTheDocument();
    expect(api.calls).toEqual([]);
  });

  it('config 503: the application is submitted and the agent lands on Pending', async () => {
    const { api, sessions } = await applicant();
    await fillAndSubmit();
    expect(await screen.findByText("We're reviewing your application.")).toBeInTheDocument();
    expect(sessions.get()?.session.scope).toBe('AGENT');
    expect(api.calls[0]).toBe('apply');
    expect(api.calls.filter((c) => c === 'apply')).toHaveLength(1);
  });

  it('config route not deployed (404, no code): same result', async () => {
    const { api, sessions } = await applicant(new ApiError(404, 'Cannot GET /agent/config', { code: null }));
    await fillAndSubmit();
    expect(await screen.findByText("We're reviewing your application.")).toBeInTheDocument();
    await waitFor(() => expect(sessions.get()?.session.scope).toBe('AGENT'));
    expect(api.calls[0]).toBe('apply');
  });
});
