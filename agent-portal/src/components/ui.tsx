import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';

export type IconName =
  | 'home'
  | 'people'
  | 'coins'
  | 'bank'
  | 'wallet'
  | 'help'
  | 'status'
  | 'signout'
  | 'copy'
  | 'check'
  | 'clock'
  | 'alert'
  | 'whatsapp';

const PATHS: Record<IconName, string> = {
  home: 'M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10',
  people: 'M9 11a3 3 0 100-6 3 3 0 000 6zM3 20c0-3.3 2.7-6 6-6s6 2.7 6 6M16 5.5a3 3 0 010 5.5M18 14c2 .7 3 2.6 3 6',
  coins: 'M12 3c4.4 0 8 1.3 8 3s-3.6 3-8 3-8-1.3-8-3 3.6-3 8-3zM4 6v6c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12v6c0 1.7 3.6 3 8 3s8-1.3 8-3v-6',
  bank: 'M3 9l9-5 9 5M5 9v8M9.5 9v8M14.5 9v8M19 9v8M3 20h18',
  wallet: 'M4 7h14a2 2 0 012 2v9a2 2 0 01-2 2H6a2 2 0 01-2-2V7zm0 0V6a2 2 0 012-2h11M16 14h.01',
  help: 'M12 21a9 9 0 100-18 9 9 0 000 18zM9.5 9.5a2.5 2.5 0 114 2c-.9.6-1.5 1-1.5 2M12 17h.01',
  status: 'M12 21a9 9 0 100-18 9 9 0 000 18zM12 7v5l3 2',
  signout: 'M9 4H5a1 1 0 00-1 1v14a1 1 0 001 1h4M16 8l4 4-4 4M20 12H9',
  copy: 'M9 9h10a1 1 0 011 1v10a1 1 0 01-1 1H9a1 1 0 01-1-1V10a1 1 0 011-1zM16 9V5a1 1 0 00-1-1H5a1 1 0 00-1 1v10a1 1 0 001 1h3',
  check: 'M5 12.5l4.5 4.5L19 7.5',
  clock: 'M12 21a9 9 0 100-18 9 9 0 000 18zM12 7v5l3 2',
  alert: 'M12 3l10 18H2L12 3zM12 10v5M12 18h.01',
  whatsapp:
    'M4 20l1.3-4.2A8 8 0 1112 20a8 8 0 01-3.8-1L4 20zM9 8.5c0 3 2.5 5.5 5.5 5.5l1-1.5-2-1-.8.8c-.8-.4-1.6-1.2-2-2l.8-.8-1-2L9 8.5z',
};

/** Decorative inline icon (no icon library is installed; these are plain SVG strokes). */
export function Icon({ name, size = 20 }: { name: IconName; size?: number }) {
  return (
    <svg
      className="icon"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d={PATHS[name]} />
    </svg>
  );
}

export function PageHeader({
  title,
  description,
  action,
}: {
  title: string;
  description?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <header className="page-header">
      <div>
        <h1>{title}</h1>
        {description && <p className="page-desc">{description}</p>}
      </div>
      {action}
    </header>
  );
}

export type Tone = 'neutral' | 'success' | 'warning' | 'danger' | 'info';

/** A status pill. The text carries the meaning; the dot and colour only reinforce it. */
export function StatusBadge({
  children,
  tone = 'neutral',
  className = '',
}: {
  children: ReactNode;
  tone?: Tone;
  className?: string;
}) {
  return (
    <span className={`badge tone-${tone} ${className}`.trim()}>
      <span className="badge-dot" aria-hidden="true" />
      {children}
    </span>
  );
}

export function SummaryCard({
  label,
  value,
  hint,
  icon,
}: {
  label: string;
  value: ReactNode;
  hint?: string;
  icon?: IconName;
}) {
  return (
    <div className="summary-card">
      <div className="summary-label">
        {icon && <Icon name={icon} size={16} />}
        {label}
      </div>
      <div className="summary-value">{value}</div>
      {hint && <div className="summary-hint">{hint}</div>}
    </div>
  );
}

export function EmptyState({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="state-box">
      <p className="state-title">{title}</p>
      {children && <p className="state-body">{children}</p>}
    </div>
  );
}

/**
 * For a feature whose service isn't deployed yet. Deliberately shows no
 * figures, rows or zero values: nothing here can be mistaken for real data.
 */
export function ComingSoonState({
  title,
  icon = 'clock',
  children,
}: {
  title: string;
  icon?: IconName;
  children: ReactNode;
}) {
  return (
    <section className="coming-soon" aria-label={title}>
      <span className="coming-soon-icon">
        <Icon name={icon} size={24} />
      </span>
      <h2>{title}</h2>
      {typeof children === 'string' ? <p>{children}</p> : children}
    </section>
  );
}

/** Pulsing placeholder lines. Purely visual; pair with a labelled `Loading`. */
export function Skeleton({ lines = 3 }: { lines?: number }) {
  return (
    <div className="skeleton" aria-hidden="true">
      {Array.from({ length: lines }, (_, i) => (
        <span key={i} className="skeleton-line" style={{ width: `${100 - i * 15}%` }} />
      ))}
    </div>
  );
}

/** Label + control + hint/error, wired together for assistive tech. */
export function FormField({
  id,
  label,
  hint,
  error,
  children,
}: {
  id: string;
  label: string;
  hint?: string;
  error?: string | null;
  children: (props: { id: string; 'aria-describedby'?: string; 'aria-invalid'?: boolean }) => ReactNode;
}) {
  const describedBy = [hint ? `${id}-hint` : null, error ? `${id}-error` : null]
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
      {hint && (
        <p className="hint" id={`${id}-hint`}>
          {hint}
        </p>
      )}
      {error && (
        <p className="error field-error" id={`${id}-error`}>
          {error}
        </p>
      )}
    </div>
  );
}

/** A card list item used by every paged list: header line + labelled facts. */
export function DataCard({
  title,
  badge,
  facts,
}: {
  title: ReactNode;
  badge?: ReactNode;
  facts: { label: string; value: ReactNode; wide?: boolean }[];
}) {
  return (
    <li className="data-card">
      <div className="data-card-head">
        <strong>{title}</strong>
        {badge}
      </div>
      <dl className="data-facts">
        {facts.map((f) => (
          <div key={f.label} className={f.wide ? 'wide' : undefined}>
            <dt>{f.label}</dt>
            <dd>{f.value}</dd>
          </div>
        ))}
      </dl>
    </li>
  );
}

export function LinkButton({ to, children }: { to: string; children: ReactNode }) {
  return (
    <Link to={to} className="button">
      {children}
    </Link>
  );
}
