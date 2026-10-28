import { useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { ErrorText } from '../components/ErrorText';
import {
  applicationRefusal,
  type ApplicationField,
  type ApplicationRefusal,
} from '../lib/applicationRefusal';
import { normalizePan, PAN_PATTERN } from '../lib/normalize';
import { setSignInNotice } from '../lib/signInNotice';
import { usePortal } from '../state/PortalContext';

/** Shown on the sign-in screen after a 401 here (see SignInPage). */
export const VERIFY_AGAIN_NOTICE =
  'Your verification has expired. Please verify your mobile number again.';

/**
 * `POST /agent/application`. The phone is never sent — it is the verified
 * sign-in phone. Success returns a full AgentSession, so the new tokens are
 * stored and the agent carries on with NO second OTP.
 *
 * Every refusal is handled as the frontend guide's §4.2 table says (see
 * `lib/applicationRefusal.ts`); nothing is shown as success unless the
 * server returned 201.
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

  const refusal = applicationRefusal(error);
  const invalid = new Set<ApplicationField>(
    refusal?.kind === 'invalidFields' ? refusal.fields : [],
  );

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

  const signInAgain = () => void signOut().then(() => navigate('/sign-in', { replace: true }));

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
      if (applicationRefusal(e)?.kind === 'verifyAgain') {
        // Drop the applicant session here too (an applicant has no refresh
        // token), then explain on sign-in why they must verify again.
        setSignInNotice(VERIFY_AGAIN_NOTICE);
        await signOut();
        navigate('/sign-in', { replace: true });
        return;
      }
      setError(e);
    } finally {
      setBusy(false);
    }
  }

  if (refusal && refusal.kind !== 'invalidFields' && refusal.kind !== 'verifyAgain') {
    return <RefusalScreen refusal={refusal} onSignInAgain={signInAgain} />;
  }

  const fieldProps = (field: ApplicationField) => ({
    'aria-invalid': invalid.has(field) || undefined,
    'aria-describedby': invalid.has(field) ? `${field}-error` : undefined,
  });
  const fieldError = (field: ApplicationField) =>
    invalid.has(field) ? (
      <p className="error field-error" id={`${field}-error`}>
        Please check this field.
      </p>
    ) : null;

  return (
    <div className="app">
      <main className="main narrow">
        <h1>Apply to become a partner</h1>
        <form onSubmit={submit} noValidate>
          <label htmlFor="name">Full name</label>
          <input id="name" value={name} maxLength={100} onChange={(e) => setName(e.target.value)} {...fieldProps('name')} />
          {fieldError('name')}
          <label htmlFor="city">City</label>
          <input id="city" value={city} maxLength={80} onChange={(e) => setCity(e.target.value)} {...fieldProps('city')} />
          {fieldError('city')}
          <label htmlFor="state">State</label>
          <input id="state" value={state} maxLength={80} onChange={(e) => setState(e.target.value)} {...fieldProps('state')} />
          {fieldError('state')}
          <label htmlFor="pan">PAN (optional)</label>
          <input
            id="pan"
            value={pan}
            maxLength={10}
            autoCapitalize="characters"
            placeholder="ABCDE1234F"
            onChange={(e) => setPan(e.target.value)}
            {...fieldProps('pan')}
          />
          {!panOk && <p className="error">PAN should look like ABCDE1234F.</p>}
          {fieldError('pan')}
          <p className="hint">
            <strong>
              PAN is optional now, but PAN and verified payout details are required before the
              first payout.
            </strong>
          </p>
          <button type="submit" disabled={!valid || busy}>
            {busy ? 'Submitting…' : 'Submit application'}
          </button>
        </form>
        <ErrorText error={error} />
        <button type="button" className="link" onClick={signInAgain}>
          Sign out
        </button>
      </main>
    </div>
  );
}

/** The screens for the refusals that end the form (guide §4.2). */
function RefusalScreen({
  refusal,
  onSignInAgain,
}: {
  refusal: Exclude<ApplicationRefusal, { kind: 'invalidFields' } | { kind: 'verifyAgain' }>;
  onSignInAgain: () => void;
}) {
  const content: Record<typeof refusal.kind, { title: string; body: string; action: string }> = {
    pending: {
      title: 'Under review',
      body: "We're reviewing your application. Sign in again to see its status.",
      action: 'Sign in again',
    },
    rejected: {
      title: 'Application not approved',
      body: 'This application cannot be submitted again.',
      action: 'Sign out',
    },
    alreadyAgent: {
      title: 'You are already a partner',
      body: 'This phone already has a partner account. Sign in again to open it.',
      action: 'Sign in again',
    },
    signInAgain: {
      title: 'Please sign in again',
      body: 'This phone has already applied, perhaps from another device. Sign in again to continue.',
      action: 'Sign in again',
    },
  };
  const c = content[refusal.kind];
  return (
    <div className="app">
      <main className="main narrow">
        <section role="status" aria-live="polite">
          <h1>{c.title}</h1>
          <p>{c.body}</p>
          <button type="button" onClick={onSignInAgain}>
            {c.action}
          </button>
        </section>
      </main>
    </div>
  );
}
