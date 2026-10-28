'use client';

import { useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { Button, Field, Loading, Notice } from '@/components/ui';
import { missingConfig } from '@/lib/config';
import { firebaseErrorMessage, useSession } from '@/lib/session';

export default function LoginPage() {
  const session = useSession();
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (session.phase === 'secondFactor') router.replace('/verify/');
    if (session.phase === 'ready') router.replace('/');
  }, [session.phase, router]);

  if (session.phase === 'unconfigured') {
    return (
      <main className="centered">
        <div className="auth-card">
          <h1>Nenjam Admin</h1>
          <Notice tone="error">
            This build is missing configuration: {missingConfig.join(', ')}. See
            admin/README.md.
          </Notice>
        </div>
      </main>
    );
  }
  if (session.phase === 'loading') return <Loading />;

  return (
    <main className="centered">
      <form
        className="auth-card"
        onSubmit={async (event) => {
          event.preventDefault();
          setBusy(true);
          setError(null);
          try {
            await session.signIn(email, password);
          } catch (e) {
            setError(firebaseErrorMessage(e));
          } finally {
            setBusy(false);
          }
        }}
      >
        <h1>Nenjam Admin</h1>
        <p className="muted">Staff sign-in. Member accounts can’t sign in here.</p>
        {session.notice ? <Notice>{session.notice}</Notice> : null}
        <Field label="Work email">
          {(props) => (
            <input
              {...props}
              type="email"
              autoComplete="username"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoFocus
            />
          )}
        </Field>
        <Field label="Password">
          {(props) => (
            <input
              {...props}
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
          )}
        </Field>
        {error ? <Notice tone="error">{error}</Notice> : null}
        <Button type="submit" tone="primary" busy={busy}>
          Continue
        </Button>
        <p className="muted small">
          Next you’ll enter a code from your authenticator app.
        </p>
      </form>
    </main>
  );
}
