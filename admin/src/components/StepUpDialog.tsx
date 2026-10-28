'use client';

import { useEffect, useRef, useState } from 'react';
import { ApiError } from '@/lib/api';
import { useSession } from '@/lib/session';
import { Button, Field, Notice } from './ui';

/**
 * Shown when the API answers ADMIN_STEP_UP_REQUIRED: sensitive permissions
 * (revealing personal data, approving refunds, paying agents, managing roles)
 * need an authenticator code from the last 10 minutes. On success the
 * original request is retried once.
 */
export function StepUpDialog() {
  const { stepUpOpen, resolveStepUp, api } = useSession();
  const ref = useRef<HTMLDialogElement>(null);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (stepUpOpen && !dialog.open) {
      setCode('');
      setError(null);
      dialog.showModal();
    } else if (!stepUpOpen && dialog.open) {
      dialog.close();
    }
  }, [stepUpOpen]);

  return (
    <dialog
      ref={ref}
      className="dialog"
      aria-labelledby="step-up-title"
      onCancel={() => resolveStepUp(false)}
    >
      <form
        onSubmit={async (event) => {
          event.preventDefault();
          setBusy(true);
          setError(null);
          try {
            await api.post('/admin/auth/step-up', { code });
            resolveStepUp(true);
          } catch (e) {
            setError(e instanceof ApiError ? e.message : 'Could not verify the code.');
          } finally {
            setBusy(false);
          }
        }}
      >
        <h2 id="step-up-title">Confirm it’s you</h2>
        <p className="muted">
          This action needs a fresh code from your authenticator app.
        </p>
        <Field label="6-digit code">
          {(props) => (
            <input
              {...props}
              inputMode="numeric"
              autoComplete="one-time-code"
              pattern="\d{6}"
              maxLength={6}
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
              autoFocus
              required
            />
          )}
        </Field>
        {error ? <Notice tone="error">{error}</Notice> : null}
        <div className="dialog-actions">
          <Button onClick={() => resolveStepUp(false)} disabled={busy}>
            Cancel
          </Button>
          <Button type="submit" tone="primary" busy={busy} disabled={code.length !== 6}>
            Confirm
          </Button>
        </div>
      </form>
    </dialog>
  );
}
