import { useEffect, useState, type FormEvent } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { ErrorText } from '../components/ErrorText';
import { MockBanner } from '../components/Layout';
import { normalizeIndianPhone, PHONE_PATTERN } from '../lib/normalize';
import { usePortal } from '../state/PortalContext';

/**
 * Phone → OTP. `POST /agent/auth/otp/request` returns a `challengeId`, which
 * is kept and sent with the code to `POST /agent/auth/otp/verify`. The
 * response is branched on `scope`: an applicant goes to the form, an agent to
 * the screen for their status.
 */
export function SignInPage() {
  const { api, stored, startSession, usingMocks } = usePortal();
  const navigate = useNavigate();
  const [phone, setPhone] = useState('');
  const [challenge, setChallenge] = useState<{ id: string; phone: string } | null>(null);
  const [code, setCode] = useState('');
  const [resendIn, setResendIn] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);

  useEffect(() => {
    if (resendIn <= 0) return;
    const t = setTimeout(() => setResendIn((s) => s - 1), 1000);
    return () => clearTimeout(t);
  }, [resendIn]);

  if (stored) return <Navigate to="/" replace />;

  const e164 = normalizeIndianPhone(phone);
  const phoneValid = PHONE_PATTERN.test(e164);

  async function sendCode(target: string) {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      const res = await api.requestOtp(target);
      setChallenge({ id: res.challengeId, phone: target });
      setResendIn(res.resendAfterSeconds);
      setCode('');
    } catch (e) {
      setError(e);
    } finally {
      setBusy(false);
    }
  }

  async function verify(event: FormEvent) {
    event.preventDefault();
    if (!challenge || busy) return;
    setBusy(true);
    setError(null);
    try {
      const session = await api.verifyOtp(challenge.id, code.trim());
      startSession(session);
      navigate(session.scope === 'APPLICANT' ? '/apply' : '/', { replace: true });
    } catch (e) {
      setError(e);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="app">
      {usingMocks && <MockBanner />}
      <main className="main narrow">
        <h1>Nenjam Partner Program</h1>
        {!challenge ? (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              if (phoneValid) void sendCode(e164);
            }}
          >
            <label htmlFor="phone">Mobile number</label>
            <input
              id="phone"
              inputMode="tel"
              autoComplete="tel"
              placeholder="98765 43210"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
            />
            <button type="submit" disabled={!phoneValid || busy}>
              Send code
            </button>
          </form>
        ) : (
          <form onSubmit={verify}>
            <p>Enter the code sent to {challenge.phone}.</p>
            <label htmlFor="code">Code</label>
            <input
              id="code"
              inputMode="numeric"
              autoComplete="one-time-code"
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 8))}
            />
            <button type="submit" disabled={code.length < 4 || busy}>
              Verify
            </button>
            <button
              type="button"
              className="link"
              disabled={resendIn > 0 || busy}
              onClick={() => void sendCode(challenge.phone)}
            >
              {resendIn > 0 ? `Resend code in ${resendIn}s` : 'Resend code'}
            </button>
            <button type="button" className="link" onClick={() => setChallenge(null)}>
              Change number
            </button>
          </form>
        )}
        <ErrorText error={error} />
        <p className="hint">Never share your OTP with anyone.</p>
      </main>
    </div>
  );
}
