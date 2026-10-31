'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useId,
  useRef,
  useState,
  type ButtonHTMLAttributes,
  type ReactNode,
} from 'react';

// --- Basics ------------------------------------------------------------------

type Tone = 'primary' | 'secondary' | 'danger' | 'ghost';

export function Button({
  tone = 'secondary',
  busy = false,
  children,
  disabled,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { tone?: Tone; busy?: boolean }) {
  return (
    <button
      type="button"
      {...rest}
      className={`btn btn-${tone} ${rest.className ?? ''}`}
      disabled={disabled || busy}
      aria-busy={busy || undefined}
    >
      {busy ? <span className="spinner" aria-hidden /> : null}
      {children}
    </button>
  );
}

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <header className="page-header">
      <div>
        <h1>{title}</h1>
        {description ? <p className="muted">{description}</p> : null}
      </div>
      {actions ? <div className="page-actions">{actions}</div> : null}
    </header>
  );
}

export function Card({
  title,
  children,
  actions,
}: {
  title?: ReactNode;
  children: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <section className="card">
      {title || actions ? (
        <div className="card-head">
          {title ? <h2>{title}</h2> : <span />}
          {actions}
        </div>
      ) : null}
      {children}
    </section>
  );
}

const BADGE_TONES: Record<string, string> = {
  ACTIVE: 'good',
  PUBLISHED: 'good',
  SUCCESS: 'good',
  PENDING: 'warn',
  PENDING_APPROVAL: 'warn',
  ON_HOLD: 'warn',
  AWAITING_VERIFICATION: 'warn',
  IN_REVIEW: 'warn',
  READY: 'warn',
  FROZEN: 'neutral',
  APPROVED: 'good',
  PAID: 'good',
  REVERSED: 'bad',
  SUBMITTED: 'warn',
  SUSPENDED: 'warn',
  DRAFT: 'info',
  EXPIRED: 'neutral',
  DISCARDED: 'neutral',
  CANCELLED: 'bad',
  REJECTED: 'bad',
  TERMINATED: 'bad',
  FAILED: 'bad',
  REFUNDED: 'bad',
};

export function Badge({ value, label }: { value: string; label?: string }) {
  return (
    <span className={`badge badge-${BADGE_TONES[value] ?? 'neutral'}`}>
      {label ?? value.replace(/_/g, ' ').toLowerCase()}
    </span>
  );
}

export function Loading({ label = 'Loading…' }: { label?: string }) {
  return (
    <div className="state" role="status" aria-live="polite">
      <span className="spinner" aria-hidden /> {label}
    </div>
  );
}

export function EmptyState({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="state empty">
      <strong>{title}</strong>
      {children ? <div className="muted">{children}</div> : null}
    </div>
  );
}

export function ErrorState({
  message,
  onRetry,
}: {
  message: string;
  onRetry?: () => void;
}) {
  return (
    <div className="state error" role="alert">
      <span>{message}</span>
      {onRetry ? <Button onClick={onRetry}>Try again</Button> : null}
    </div>
  );
}

export function Notice({
  tone = 'info',
  children,
}: {
  tone?: 'info' | 'warn' | 'error' | 'success';
  children: ReactNode;
}) {
  return (
    <div className={`notice notice-${tone}`} role={tone === 'error' ? 'alert' : 'note'}>
      {children}
    </div>
  );
}

export function Field({
  label,
  hint,
  error,
  children,
}: {
  label: string;
  hint?: ReactNode;
  error?: string | null;
  children: (props: { id: string; 'aria-describedby'?: string; 'aria-invalid'?: boolean }) => ReactNode;
}) {
  const id = useId();
  const hintId = `${id}-hint`;
  const errorId = `${id}-error`;
  const describedBy = [hint ? hintId : null, error ? errorId : null]
    .filter(Boolean)
    .join(' ');
  return (
    <div className="field">
      <label htmlFor={id}>{label}</label>
      {children({
        id,
        'aria-describedby': describedBy || undefined,
        'aria-invalid': error ? true : undefined,
      })}
      {hint ? (
        <small id={hintId} className="muted">
          {hint}
        </small>
      ) : null}
      {error ? (
        <small id={errorId} className="field-error">
          {error}
        </small>
      ) : null}
    </div>
  );
}

// --- Dialogs -------------------------------------------------------------------

/**
 * A modal built on <dialog> (focus trapping and Escape for free). Sensitive
 * actions pass `requireReason`: the reason is mandatory and is stored in the
 * audit log by the API.
 */
export function ConfirmDialog({
  open,
  title,
  children,
  confirmLabel,
  tone = 'primary',
  requireReason = false,
  reasonLabel = 'Reason (kept in the audit log)',
  onConfirm,
  onClose,
}: {
  open: boolean;
  title: string;
  children?: ReactNode;
  confirmLabel: string;
  tone?: Tone;
  requireReason?: boolean;
  reasonLabel?: string;
  /** Throw to keep the dialog open and show the error. */
  onConfirm: (reason: string) => Promise<void>;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) {
      setReason('');
      setError(null);
      dialog.showModal();
    } else if (!open && dialog.open) {
      dialog.close();
    }
  }, [open]);

  const reasonOk = !requireReason || reason.trim().length >= 3;

  return (
    <dialog ref={ref} className="dialog" onClose={onClose} aria-labelledby="dialog-title">
      <form
        method="dialog"
        onSubmit={async (event) => {
          event.preventDefault();
          if (!reasonOk) return;
          setBusy(true);
          setError(null);
          try {
            await onConfirm(reason.trim());
            onClose();
          } catch (e) {
            setError(e instanceof Error ? e.message : 'Something went wrong.');
          } finally {
            setBusy(false);
          }
        }}
      >
        <h2 id="dialog-title">{title}</h2>
        {children}
        {requireReason ? (
          <Field label={reasonLabel} hint="At least 3 characters.">
            {(props) => (
              <textarea
                {...props}
                rows={3}
                value={reason}
                maxLength={500}
                onChange={(e) => setReason(e.target.value)}
                required
              />
            )}
          </Field>
        ) : null}
        {error ? <Notice tone="error">{error}</Notice> : null}
        <div className="dialog-actions">
          <Button onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          <Button type="submit" tone={tone} busy={busy} disabled={!reasonOk}>
            {confirmLabel}
          </Button>
        </div>
      </form>
    </dialog>
  );
}

// --- Toasts --------------------------------------------------------------------

interface Toast {
  id: number;
  tone: 'success' | 'error';
  message: string;
}

const ToastContext = createContext<(tone: Toast['tone'], message: string) => void>(
  () => undefined,
);

/** Success toasts are only ever shown after the API confirmed the change. */
export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const push = useCallback((tone: Toast['tone'], message: string) => {
    const id = Date.now() + Math.random();
    setToasts((list) => [...list, { id, tone, message }]);
    window.setTimeout(
      () => setToasts((list) => list.filter((t) => t.id !== id)),
      tone === 'error' ? 8000 : 4000,
    );
  }, []);
  return (
    <ToastContext.Provider value={push}>
      {children}
      <div className="toasts" aria-live="polite" role="status">
        {toasts.map((toast) => (
          <div key={toast.id} className={`toast toast-${toast.tone}`}>
            {toast.message}
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast() {
  return useContext(ToastContext);
}
