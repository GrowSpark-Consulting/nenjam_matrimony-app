import { useCallback, useState, type FormEvent } from 'react';
import { Link, Navigate, useNavigate, useParams } from 'react-router-dom';
import type { ClientDraft, ClientStatus } from '../api/types';
import { ErrorText } from '../components/ErrorText';
import { Loading } from '../components/Loading';
import { EmptyState, FormField, Icon, LinkButton, PageHeader, StatusBadge } from '../components/ui';
import { useAsync } from '../components/useAsync';
import { usePaged } from '../components/usePaged';
import { clientErrorMessage, clientsAvailable, isOpen, missingText } from '../lib/clientsFeature';
import { pickLabel } from '../lib/labels';
import { usePortal } from '../state/PortalContext';
import { ClientEditor, clientTone, initial } from './ClientEditor';

const STATUSES: ClientStatus[] = ['DRAFT', 'WAITING_FOR_CLIENT', 'ACCEPTED', 'REJECTED', 'EXPIRED'];
const E164 = /^\+[1-9]\d{7,14}$/;


/** Hides the whole feature unless the server switched it on for this agent. */
function useClientsGate() {
  const { config, agent, configLoading } = usePortal();
  return { ok: clientsAvailable(config, agent), loading: configLoading && !config, config, agent };
}

function Gate({ children }: { children: (g: ReturnType<typeof useClientsGate>) => React.ReactNode }) {
  const g = useClientsGate();
  if (g.loading) return <Loading />;
  if (!g.ok) return <Navigate to="/" replace />;
  return <>{children(g)}</>;
}

// ─── List ────────────────────────────────────────────────────────────

export function ClientsPage() {
  return <Gate>{(g) => <ClientsList paused={g.agent?.status === 'SUSPENDED'} />}</Gate>;
}

function ClientsList({ paused }: { paused: boolean }) {
  const { api, config } = usePortal();
  const [status, setStatus] = useState<ClientStatus | ''>('');
  const list = usePaged<ClientDraft>(
    useCallback(
      (cursor: string | null) => api.listClients({ cursor, status: status || undefined }),
      [api, status],
    ),
  );
  const limit = config?.clients?.draftLimit ?? null;
  const open = list.items.filter(isOpen).length;

  return (
    <>
      <PageHeader
        title="Your clients"
        description={
          config?.clients?.expiryDays
            ? `Your client has ${config.clients.expiryDays} days to answer after you submit.`
            : 'Profiles you are setting up for the people you help.'
        }
        action={!paused ? <LinkButton to="/clients/new">Add a client</LinkButton> : undefined}
      />
      {paused && <p className="notice">Your account is paused. You can look, but not change anything.</p>}
      {limit !== null && (
        <p className="hint open-count" aria-label="Open clients">
          {open} of {limit} open
        </p>
      )}
      <div className="chips" role="group" aria-label="Filter by status">
        {(['', ...STATUSES] as const).map((s) => (
          <button
            key={s || 'all'}
            type="button"
            className="chip"
            aria-pressed={status === s}
            onClick={() => setStatus(s)}
          >
            {s === '' ? 'All' : pickLabel(config?.clientStatusLabels?.[s], s)}
          </button>
        ))}
      </div>
      {list.loading && list.items.length === 0 && <Loading />}
      <ErrorText error={list.error} onRetry={list.retry} />
      {!list.loading && !list.error && list.items.length === 0 && (
        <EmptyState title={status ? 'No clients with this status' : 'No clients yet'}>
          {status ? 'Try another status, or choose All.' : paused ? undefined : 'Tap “Add a client” to start a profile.'}
        </EmptyState>
      )}
      <ul className="list">
        {list.items.map((c) => (
          <li key={c.id} className="data-card client-card">
            <div className="client-card-main">
              <span className="avatar" aria-hidden="true">{initial(c.displayName)}</span>
              <div className="client-card-text">
                <Link to={`/clients/${c.id}`} className="client-link">
                  {c.displayName}
                </Link>
                <span className="hint">{c.phoneMasked}</span>
              </div>
              <Icon name="chevron" size={18} />
            </div>
            <div className="client-card-meta">
              <StatusBadge tone={clientTone(c.status)}>
                {pickLabel(c.statusLabel ?? config?.clientStatusLabels?.[c.status], c.status)}
              </StatusBadge>
              {c.expiresOn && isOpen(c) && <span className="hint">Open until {c.expiresOn}</span>}
              {c.status === 'DRAFT' && <span className="hint">{missingText(c.missingRequired)}</span>}
            </div>
          </li>
        ))}
      </ul>
      {list.cursor && (
        <button type="button" className="secondary load-more" onClick={list.loadMore} disabled={list.loading}>
          {list.loading ? 'Loading…' : 'Load more'}
        </button>
      )}
    </>
  );
}

// ─── Add ─────────────────────────────────────────────────────────────

export function AddClientPage() {
  return <Gate>{(g) => (g.agent?.status === 'ACTIVE' ? <AddClientForm /> : <Navigate to="/clients" replace />)}</Gate>;
}

function AddClientForm() {
  const { api, config } = usePortal();
  const navigate = useNavigate();
  const [phone, setPhone] = useState('');
  const [consent, setConsent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [phoneError, setPhoneError] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    const p = phone.replace(/[\s-]/g, '');
    if (!E164.test(p)) {
      setPhoneError('Enter the number with the country code, like +919876543210.');
      return;
    }
    setPhoneError(null);
    setBusy(true);
    setError(null);
    try {
      // No details yet: the sections are filled in on the next screen.
      const draft = await api.createClient({ phone: p, consentConfirmed: true });
      navigate(`/clients/${draft.id}`, { replace: true });
    } catch (err) {
      setError(err);
      setBusy(false);
    }
  }

  return (
    <>
      <PageHeader title="Add a client" description="Her profile is always her own. Start with her mobile number." />
      <p className="hint">
        <Link to="/clients">← All clients</Link>
      </p>
      <form onSubmit={(e) => void submit(e)} className="card form-card" noValidate>
        <FormField id="client-phone" label="Her mobile number" hint="With country code, like +919876543210." error={phoneError} required>
          {(p) => (
            <input
              {...p}
              type="tel"
              inputMode="tel"
              autoComplete="off"
              enterKeyHint="go"
              placeholder="+919876543210"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
            />
          )}
        </FormField>
        <label className="check">
          <input type="checkbox" checked={consent} onChange={(e) => setConsent(e.target.checked)} />
          The client (or her family) agreed to be added.
        </label>
        {error != null && (
          <p className="error" role="alert">
            {clientErrorMessage(error, config?.clients?.draftLimit)}
          </p>
        )}
        <div className="actions">
          <button type="submit" disabled={!consent || busy}>
            {busy ? 'Adding…' : 'Add client'}
          </button>
        </div>
      </form>
    </>
  );
}

// ─── Draft editor ────────────────────────────────────────────────────

export function ClientDetailPage() {
  return <Gate>{(g) => <ClientLoader paused={g.agent?.status === 'SUSPENDED'} />}</Gate>;
}

function ClientLoader({ paused }: { paused: boolean }) {
  const { api } = usePortal();
  const { id = '' } = useParams();
  const state = useAsync(useCallback(() => api.getClient(id), [api, id]));
  if (state.loading) return <Loading />;
  if (state.error || !state.data) return <ErrorText error={state.error} onRetry={state.reload} />;
  return <ClientEditor key={state.data.id} initial={state.data} paused={paused} />;
}
