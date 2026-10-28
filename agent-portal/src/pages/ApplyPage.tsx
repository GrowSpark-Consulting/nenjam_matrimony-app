import { useState, type FormEvent } from 'react';
import { ApiError } from '../api/errors';
import { useNavigate } from 'react-router-dom';
import { ErrorText } from '../components/ErrorText';
import { normalizePan, PAN_PATTERN } from '../lib/normalize';
import { usePortal } from '../state/PortalContext';

/**
 * `POST /agent/application`. The phone is never sent — it is the verified
 * sign-in phone. Success returns a full AgentSession, so the new tokens are
 * stored and the agent carries on with NO second OTP.
 *
 * Refusals (contract): `409 APPLICATION_EXISTS` (already under review or
 * already an agent; `agentStatus` says which, or is absent when the agent
 * record belongs to another session) and `403 AGENT_NOT_ACTIVE` with
 * `agentStatus: REJECTED` (re-applying is switched off). Both show the
 * server's own message plus a "Sign in again" action: signing in again
 * returns the agent session that shows the real status. No other code is
 * assumed.
 */
export function ApplyPage() {
  const { api, startSession, signOut } = usePortal();
  const navigate = useNavigate();
  const [name, setName] = useState('');
  const [city, setCity] = useState('');
  const [state, setState] = useState('');
  const [pan, setPan] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);

  const panValue = normalizePan(pan);
  const panOk = panValue === '' || PAN_PATTERN.test(panValue);
  const valid =
    name.trim().length >= 2 &&
    name.trim().length <= 100 &&
    city.trim().length >= 1 &&
    city.trim().length <= 80 &&
    state.trim().length >= 1 &&
    state.trim().length <= 80 &&
    panOk;

  const mustSignInAgain =
    error instanceof ApiError &&
    ((error.status === 409 && error.code === 'APPLICATION_EXISTS') ||
      (error.status === 403 && error.code === 'AGENT_NOT_ACTIVE'));

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const session = await api.apply({
        name: name.trim(),
        city: city.trim(),
        state: state.trim(),
        ...(panValue ? { pan: panValue } : {}),
      });
      startSession(session);
      navigate('/status', { replace: true });
    } catch (e) {
      setError(e);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="app">
      <main className="main narrow">
        <h1>Apply to become a partner</h1>
        <form onSubmit={submit}>
          <label htmlFor="name">Full name</label>
          <input id="name" value={name} maxLength={100} onChange={(e) => setName(e.target.value)} />
          <label htmlFor="city">City</label>
          <input id="city" value={city} maxLength={80} onChange={(e) => setCity(e.target.value)} />
          <label htmlFor="state">State</label>
          <input id="state" value={state} maxLength={80} onChange={(e) => setState(e.target.value)} />
          <label htmlFor="pan">PAN (optional)</label>
          <input
            id="pan"
            value={pan}
            maxLength={10}
            autoCapitalize="characters"
            placeholder="ABCDE1234F"
            onChange={(e) => setPan(e.target.value)}
          />
          {!panOk && <p className="error">PAN should look like ABCDE1234F.</p>}
          <p className="hint">
            <strong>
              PAN is optional now, but PAN and verified payout details are required before the
              first payout.
            </strong>
          </p>
          <button type="submit" disabled={!valid || busy}>
            Submit application
          </button>
        </form>
        <ErrorText error={error} />
        {mustSignInAgain && (
          <button type="button" onClick={() => void signOut().then(() => navigate('/sign-in'))}>
            Sign in again
          </button>
        )}
        <button className="link" onClick={() => void signOut()}>
          Sign out
        </button>
      </main>
    </div>
  );
}
