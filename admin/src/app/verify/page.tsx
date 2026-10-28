'use client';

import { useRouter } from 'next/navigation';
import QRCode from 'qrcode';
import { useEffect, useState } from 'react';
import { Button, Field, Loading, Notice } from '@/components/ui';
import { ApiError } from '@/lib/api';
import { useSession } from '@/lib/session';

type Step = 'code' | 'enrolCode' | 'enrolScan';

/**
 * The second factor. An enrolled admin types the current code; a new admin
 * first enters the one-time enrolment code a Super Admin gave them, scans
 * the QR code into an authenticator app, and confirms with its first code.
 */
export default function VerifyPage() {
  const session = useSession();
  const router = useRouter();
  const [step, setStep] = useState<Step>('code');
  const [code, setCode] = useState('');
  const [enrollmentCode, setEnrollmentCode] = useState('');
  const [secret, setSecret] = useState<string | null>(null);
  const [qr, setQr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (session.phase === 'signedOut' || session.phase === 'unconfigured') {
      router.replace('/login/');
    }
    if (session.phase === 'ready') router.replace('/');
  }, [session.phase, router]);

  if (session.phase === 'loading') return <Loading />;
  if (session.phase === 'notStaff') {
    return (
      <main className="centered">
        <div className="auth-card">
          <h1>No admin access</h1>
          <p>{session.email} is not an active admin.</p>
          <Button onClick={() => void session.signOut()}>Sign out</Button>
        </div>
      </main>
    );
  }

  const fail = (e: unknown) => {
    if (e instanceof ApiError && e.code === 'ADMIN_MFA_NOT_ENROLLED') {
      setStep('enrolCode');
      setError(null);
      return;
    }
    if (e instanceof ApiError && e.code === 'ADMIN_ACCESS_REQUIRED') {
      setError('This account is not an active admin.');
      return;
    }
    setError(e instanceof Error ? e.message : 'Something went wrong.');
  };

  const codeInput = (
    <Field label="6-digit code from your authenticator app">
      {(props) => (
        <input
          {...props}
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="\d{6}"
          maxLength={6}
          value={code}
          onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
          required
          autoFocus
        />
      )}
    </Field>
  );

  return (
    <main className="centered">
      <form
        className="auth-card"
        onSubmit={async (event) => {
          event.preventDefault();
          setBusy(true);
          setError(null);
          try {
            if (step === 'code') {
              await session.verifyCode(code);
            } else if (step === 'enrolCode') {
              const started = await session.startEnrollment(enrollmentCode);
              setSecret(started.secret);
              setQr(await QRCode.toDataURL(started.otpauthUri, { margin: 1, width: 200 }));
              setStep('enrolScan');
            } else {
              await session.confirmEnrollment(enrollmentCode, code);
            }
          } catch (e) {
            fail(e);
          } finally {
            setBusy(false);
          }
        }}
      >
        <h1>{step === 'code' ? 'Enter your code' : 'Set up your authenticator'}</h1>
        <p className="muted">Signed in as {session.email}.</p>
        {session.notice ? <Notice>{session.notice}</Notice> : null}

        {step === 'code' ? codeInput : null}

        {step === 'enrolCode' ? (
          <>
            <p>
              Enter the one-time enrolment code a Super Admin gave you. It’s valid for 24
              hours.
            </p>
            <Field label="Enrolment code" hint="Looks like K7Q2M-XR9TB.">
              {(props) => (
                <input
                  {...props}
                  autoComplete="off"
                  value={enrollmentCode}
                  onChange={(e) => setEnrollmentCode(e.target.value.toUpperCase())}
                  required
                  autoFocus
                />
              )}
            </Field>
          </>
        ) : null}

        {step === 'enrolScan' && secret ? (
          <>
            <p>
              Scan this with Google Authenticator, Microsoft Authenticator or 1Password,
              then enter the code it shows.
            </p>
            {qr ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img className="qr" src={qr} alt="QR code for your authenticator app" />
            ) : null}
            <details>
              <summary>Can’t scan? Enter the key by hand</summary>
              <code className="secret">{secret.replace(/(.{4})/g, '$1 ').trim()}</code>
            </details>
            {codeInput}
          </>
        ) : null}

        {error ? <Notice tone="error">{error}</Notice> : null}
        <Button type="submit" tone="primary" busy={busy}>
          {step === 'enrolCode' ? 'Continue' : 'Verify'}
        </Button>
        <div className="auth-links">
          {step === 'code' ? (
            <button type="button" className="link" onClick={() => setStep('enrolCode')}>
              First time? Set up your authenticator
            </button>
          ) : (
            <button type="button" className="link" onClick={() => setStep('code')}>
              I already have an authenticator set up
            </button>
          )}
          <button type="button" className="link" onClick={() => void session.signOut()}>
            Use a different account
          </button>
        </div>
      </form>
    </main>
  );
}
