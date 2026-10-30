import { act, render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { useEffect } from 'react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import type { ApiSetup } from './api';
import { HttpAgentApi } from './api/agentApi';
import { ApiError } from './api/errors';
import { HttpClient } from './api/http';
import { MockAgentApi } from './api/mockAgentApi';
import { SessionStore } from './api/session';
import type { AgentConfig, AgentProfile } from './api/types';
import { AppRoutes } from './App';
import { PROGRAM_UNAVAILABLE_MESSAGE } from './components/ErrorText';
import { PortalProvider, usePortal } from './state/PortalContext';

const PENDING = '+919000000001';
const SERVER_TROUBLE = 'The service is having trouble right now. Please try again shortly.';
const PENDING_TEXT = "We're reviewing your application.";

const serverError = (status = 500) =>
  new ApiError(status, 'internal stack trace /srv/app.js:1', { code: null });
const programUnavailable = () =>
  new ApiError(503, 'The agent program is not available yet.', {
    code: 'AGENT_PROGRAM_UNAVAILABLE',
  });

/** A mock whose two portal-load calls can be scripted and counted. */
class ScriptedApi extends MockAgentApi {
  meCalls = 0;
  cfgCalls = 0;
  me?: (call: number) => Promise<AgentProfile>;
  cfg?: (call: number) => Promise<AgentConfig>;
  override getMe(): Promise<AgentProfile> {
    this.meCalls += 1;
    return this.me ? this.me(this.meCalls) : super.getMe();
  }
  override getConfig(): Promise<AgentConfig> {
    this.cfgCalls += 1;
    return this.cfg ? this.cfg(this.cfgCalls) : super.getConfig();
  }
  realMe() {
    return super.getMe();
  }
}

async function signedIn(phone = PENDING) {
  window.localStorage.clear();
  const sessions = new SessionStore(window.localStorage);
  const api = new ScriptedApi(sessions);
  const { challengeId } = await api.requestOtp(phone);
  sessions.set(await api.verifyOtp(challengeId, '123456'));
  const setup: ApiSetup = { api, sessions, usingMocks: true };
  return { api, sessions, setup };
}

function Spy({ log }: { log: string[] }) {
  const { pathname } = useLocation();
  useEffect(() => {
    log.push(pathname);
  }, [pathname, log]);
  return null;
}

function ReloadButton() {
  const { reloadAgent } = usePortal();
  return <button onClick={reloadAgent}>test-reload</button>;
}

function renderAt(path: string, setup: ApiSetup, log: string[] = []) {
  return render(
    <PortalProvider setup={setup}>
      <MemoryRouter initialEntries={[path]}>
        <Spy log={log} />
        <AppRoutes />
      </MemoryRouter>
      <ReloadButton />
    </PortalProvider>,
  );
}

const settle = () => act(() => new Promise((r) => setTimeout(r, 40)));

describe('/agent/me failures', () => {
  it('500: shows a message and Try again, keeps the session, never leaks server text', async () => {
    const { api, sessions, setup } = await signedIn();
    api.me = () => Promise.reject(serverError(500));
    renderAt('/status', setup);
    expect(await screen.findByRole('alert')).toHaveTextContent(SERVER_TROUBLE);
    expect(screen.getByRole('button', { name: 'Try again' })).toBeInTheDocument();
    expect(document.body).not.toHaveTextContent('stack trace');
    expect(sessions.get()).not.toBeNull();
  });

  it('503: no blank page and no redirect loop (one request, one location)', async () => {
    const { api, sessions, setup } = await signedIn();
    api.me = () => Promise.reject(serverError(503));
    const log: string[] = [];
    renderAt('/', setup, log);
    expect(await screen.findByText("We couldn't load your account")).toBeInTheDocument();
    await settle();
    expect(log).toEqual(['/']); // never bounced to /sign-in and back
    expect(api.meCalls).toBe(1); // no request storm
    expect(sessions.get()).not.toBeNull();
  });

  it('a network failure is recoverable too', async () => {
    const { api, setup } = await signedIn();
    api.me = () => Promise.reject(ApiError.network());
    renderAt('/status', setup);
    expect(await screen.findByRole('alert')).toHaveTextContent("Couldn't reach Nenjam");
  });

  it('Try again after a 503 shows the status and clears the error, one request per click', async () => {
    const { api, setup } = await signedIn();
    let release: (p: AgentProfile) => void = () => {};
    api.me = (call) =>
      call === 1
        ? Promise.reject(serverError(503))
        : new Promise<AgentProfile>((resolve) => {
            release = resolve;
          });
    const user = userEvent.setup();
    renderAt('/status', setup);
    await user.click(await screen.findByRole('button', { name: 'Try again' }));
    // Loading feedback while retrying; the error is hidden.
    expect(await screen.findByRole('status')).toBeInTheDocument();
    expect(screen.queryByRole('alert')).toBeNull();
    expect(api.meCalls).toBe(2);
    await act(async () => release(await api.realMe()));
    expect(await screen.findByText(PENDING_TEXT)).toBeInTheDocument();
    expect(screen.queryByRole('alert')).toBeNull();
    expect(api.meCalls).toBe(2);
  });

  it('does not start a second request while a retry is in flight', async () => {
    const { api, setup } = await signedIn();
    api.me = (call) => (call === 1 ? Promise.reject(serverError(500)) : new Promise(() => {}));
    const user = userEvent.setup();
    renderAt('/status', setup);
    const retry = await screen.findByRole('button', { name: 'Try again' });
    await user.click(retry);
    await settle();
    expect(api.meCalls).toBe(2);
    await user.click(screen.getByRole('button', { name: 'test-reload' })); // forced reload is allowed
    expect(api.meCalls).toBe(3);
  });

  it('401 follows the session-expiry flow: the real HttpClient clears it and sign-in shows', async () => {
    const { api: mock, sessions } = await signedIn();
    const fetchStub = (() =>
      Promise.resolve(
        new Response(
          JSON.stringify({ statusCode: 401, error: 'Unauthorized', code: 'UNAUTHORIZED', message: 'x' }),
          { status: 401 },
        ),
      )) as unknown as typeof fetch;
    const api = new HttpAgentApi(new HttpClient('https://api.test', sessions, fetchStub, null));
    void mock;
    renderAt('/status', { api, sessions, usingMocks: false });
    expect(await screen.findByLabelText('Mobile number')).toBeInTheDocument();
    expect(sessions.get()).toBeNull();
  });

  it('404 AGENT_NOT_FOUND on an agent session is an error screen, not a redirect', async () => {
    const { api, sessions, setup } = await signedIn();
    api.me = () =>
      Promise.reject(new ApiError(404, 'No application yet.', { code: 'AGENT_NOT_FOUND' }));
    const log: string[] = [];
    renderAt('/', setup, log);
    expect(await screen.findByRole('button', { name: 'Try again' })).toBeInTheDocument();
    await settle();
    expect(log).toEqual(['/']);
    expect(sessions.get()).not.toBeNull();
  });

  it('applicant flow: an applicant goes to the form and /agent/me is never called', async () => {
    window.localStorage.clear();
    const sessions = new SessionStore(window.localStorage);
    const api = new ScriptedApi(sessions);
    const { challengeId } = await api.requestOtp('+919876543210'); // no agent record
    sessions.set(await api.verifyOtp(challengeId, '123456'));
    expect(sessions.get()?.session.scope).toBe('APPLICANT');
    renderAt('/status', { api, sessions, usingMocks: true });
    expect(await screen.findByText('Apply to become a partner')).toBeInTheDocument();
    expect(api.meCalls).toBe(0);
  });
});

describe('/agent/config failures', () => {
  it('config 503 with /agent/me ok: the status page stays, config error has Try again', async () => {
    const { api, setup } = await signedIn();
    api.cfg = () => Promise.reject(programUnavailable());
    renderAt('/status', setup);
    expect(await screen.findByText(PENDING_TEXT)).toBeInTheDocument();
    expect(await screen.findByRole('alert')).toHaveTextContent(PROGRAM_UNAVAILABLE_MESSAGE);
    expect(screen.getByRole('button', { name: 'Try again' })).toBeInTheDocument();
  });

  it('config retry succeeds: the error clears without signing in again', async () => {
    const { api, sessions, setup } = await signedIn();
    api.cfg = (call) => (call === 1 ? Promise.reject(programUnavailable()) : super_config(api));
    const user = userEvent.setup();
    renderAt('/status', setup);
    await user.click(await screen.findByRole('button', { name: 'Try again' }));
    await waitFor(() => expect(screen.queryByRole('alert')).toBeNull());
    expect(screen.getByText(PENDING_TEXT)).toBeInTheDocument();
    expect(api.cfgCalls).toBe(2);
    expect(api.meCalls).toBe(1); // only config was retried
    expect(sessions.get()).not.toBeNull();
  });

  it('both fail: a recoverable screen; retrying /me brings the page back, config error stays', async () => {
    const { api, sessions, setup } = await signedIn();
    api.me = (call) => (call === 1 ? Promise.reject(serverError(500)) : api.realMe());
    api.cfg = () => Promise.reject(programUnavailable());
    const user = userEvent.setup();
    renderAt('/status', setup);
    expect(await screen.findByText("We couldn't load your account")).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Try again' }));
    expect(await screen.findByText(PENDING_TEXT)).toBeInTheDocument();
    expect(await screen.findByRole('alert')).toHaveTextContent(PROGRAM_UNAVAILABLE_MESSAGE);
    expect(sessions.get()).not.toBeNull();
  });

  it('a failed refresh keeps the last good profile and shows an error', async () => {
    const { api, setup } = await signedIn();
    api.me = (call) => (call === 1 ? api.realMe() : Promise.reject(serverError(503)));
    const user = userEvent.setup();
    renderAt('/status', setup);
    expect(await screen.findByText(PENDING_TEXT)).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'test-reload' }));
    expect(await screen.findByRole('alert')).toHaveTextContent(SERVER_TROUBLE);
    expect(screen.getByText(PENDING_TEXT)).toBeInTheDocument(); // stale copy still shown
  });
});

describe('stale requests', () => {
  it('an older /agent/me answer cannot overwrite a newer one', async () => {
    const { api, setup } = await signedIn();
    const resolvers: Array<(p: AgentProfile) => void> = [];
    api.me = () => new Promise<AgentProfile>((resolve) => resolvers.push(resolve));
    const user = userEvent.setup();
    renderAt('/status', setup);
    await user.click(screen.getByRole('button', { name: 'test-reload' })); // request 2 supersedes 1
    expect(resolvers).toHaveLength(2);
    const base = await api.realMe();
    await act(async () => resolvers[1]({ ...base, name: 'Newer Name' }));
    expect((await screen.findAllByText('Newer Name')).length).toBeGreaterThan(0);
    await act(async () => resolvers[0]({ ...base, name: 'Older Name' }));
    expect(screen.queryByText('Older Name')).toBeNull();
    expect(screen.getAllByText('Newer Name').length).toBeGreaterThan(0);
  });
});

function super_config(api: ScriptedApi): Promise<AgentConfig> {
  return MockAgentApi.prototype.getConfig.call(api);
}
