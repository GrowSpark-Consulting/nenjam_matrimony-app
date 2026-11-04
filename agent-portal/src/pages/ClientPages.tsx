import { useCallback, useMemo, useState, type FormEvent } from 'react';
import { Link, Navigate, useNavigate, useParams } from 'react-router-dom';
import { ApiError } from '../api/errors';
import type { ClientDetails, ClientDraft, ClientStatus, RefItem } from '../api/types';
import { ErrorText } from '../components/ErrorText';
import { Loading } from '../components/Loading';
import { DataCard, EmptyState, FormField, LinkButton, PageHeader, StatusBadge } from '../components/ui';
import { useAsync } from '../components/useAsync';
import { usePaged } from '../components/usePaged';
import {
  getPath,
  isAnswered,
  normalizeDetails,
  sectionOf,
  SECTIONS,
  setAnswer,
  setPath,
  type FieldDef,
  type SiblingRow,
} from '../lib/clientProfile';
import { clientErrorMessage, clientsAvailable, isOpen, missingText } from '../lib/clientsFeature';
import { pickLabel } from '../lib/labels';
import { usePortal } from '../state/PortalContext';

const STATUSES: ClientStatus[] = ['DRAFT', 'WAITING_FOR_CLIENT', 'ACCEPTED', 'REJECTED', 'EXPIRED'];
const E164 = /^\+[1-9]\d{7,14}$/;

function tone(s: ClientStatus) {
  return s === 'ACCEPTED' ? 'success' : s === 'DRAFT' || s === 'WAITING_FOR_CLIENT' ? 'info' : 'neutral';
}

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
            : undefined
        }
        action={!paused ? <LinkButton to="/clients/new">Add a client</LinkButton> : undefined}
      />
      {paused && <p className="notice">Your account is paused. You can look, but not change anything.</p>}
      {limit !== null && (
        <p className="hint" aria-label="Open clients">
          {open} of {limit} open
        </p>
      )}
      <div className="toolbar">
        <label htmlFor="client-status">Status</label>
        <select id="client-status" value={status} onChange={(e) => setStatus(e.target.value as ClientStatus | '')}>
          <option value="">All</option>
          {STATUSES.map((s) => (
            <option key={s} value={s}>
              {pickLabel(config?.clientStatusLabels?.[s], s)}
            </option>
          ))}
        </select>
      </div>
      {list.loading && list.items.length === 0 && <Loading />}
      <ErrorText error={list.error} onRetry={list.retry} />
      {!list.loading && !list.error && list.items.length === 0 && (
        <EmptyState title="No clients here yet">Add a client to start a profile for her.</EmptyState>
      )}
      <ul className="list">
        {list.items.map((c) => (
          <DataCard
            key={c.id}
            title={<Link to={`/clients/${c.id}`}>{c.displayName}</Link>}
            badge={
              <StatusBadge tone={tone(c.status)}>
                {pickLabel(c.statusLabel ?? config?.clientStatusLabels?.[c.status], c.status)}
              </StatusBadge>
            }
            facts={[
              { label: 'Phone', value: c.phoneMasked },
              ...(c.expiresOn && isOpen(c) ? [{ label: 'Open until', value: c.expiresOn }] : []),
              ...(c.status === 'DRAFT' ? [{ label: 'Progress', value: missingText(c.missingRequired) }] : []),
            ]}
          />
        ))}
      </ul>
      {list.cursor && (
        <button type="button" className="secondary" onClick={list.loadMore} disabled={list.loading}>
          Load more
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
      <form onSubmit={(e) => void submit(e)} className="card form-card" noValidate>
        <FormField id="client-phone" label="Her mobile number" hint="With country code, like +919876543210." error={phoneError}>
          {(p) => (
            <input {...p} type="tel" inputMode="tel" autoComplete="off" value={phone} onChange={(e) => setPhone(e.target.value)} />
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
        <button type="submit" disabled={!consent || busy}>
          {busy ? 'Adding…' : 'Add client'}
        </button>
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

/** Order-independent compare of two normalised bodies. */
function stable(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(stable).join(',')}]`;
  if (v && typeof v === 'object') {
    return `{${Object.keys(v as object)
      .sort()
      .map((k) => `${k}:${stable((v as Record<string, unknown>)[k])}`)
      .join(',')}}`;
  }
  return JSON.stringify(v);
}

function ClientEditor({ initial, paused }: { initial: ClientDraft; paused: boolean }) {
  const { api, config } = usePortal();
  const navigate = useNavigate();
  const [draft, setDraft] = useState(initial);
  // The WHOLE working profile. Every save sends all of it, never one section.
  const [details, setDetails] = useState<ClientDetails>(initial.details ?? {});
  const [index, setIndex] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<unknown>(null);
  const [problems, setProblems] = useState<{ path: string; message: string }[]>([]);
  const [confirming, setConfirming] = useState(false);
  const [confirmDiscard, setConfirmDiscard] = useState(false);

  const editable = draft.editable && !paused;
  const limit = config?.clients?.draftLimit ?? null;
  const section = SECTIONS[index];
  const dirty = useMemo(
    () => stable(normalizeDetails(details).details) !== stable(normalizeDetails(draft.details ?? {}).details),
    [details, draft.details],
  );

  async function save(): Promise<ClientDraft | null> {
    const { details: body, errors } = normalizeDetails(details);
    setProblems(errors);
    if (errors.length > 0) {
      const first = SECTIONS.findIndex((s) => s.key === sectionOf(errors[0].path));
      if (first >= 0) setIndex(first);
      return null;
    }
    setBusy(true);
    setError(null);
    try {
      // Complete merged profile; the server replaces its copy with this.
      const next = await api.updateClient(draft.id, body);
      setDraft(next);
      setDetails(next.details ?? {});
      return next;
    } catch (e) {
      setError(e);
      return null;
    } finally {
      setBusy(false);
    }
  }

  async function saveAndNext() {
    const ok = await save();
    if (ok && index < SECTIONS.length - 1) setIndex(index + 1);
  }

  /** Skip only moves on. It never clears, saves or edits anything. */
  function skip() {
    setIndex(Math.min(index + 1, SECTIONS.length - 1));
  }

  async function submit() {
    setConfirming(false);
    setBusy(true);
    setError(null);
    try {
      const next = await api.submitClient(draft.id);
      setDraft(next);
      setDetails(next.details ?? {});
    } catch (e) {
      setError(e);
      if (e instanceof ApiError && e.code === 'CLIENT_PROFILE_INCOMPLETE') {
        const first = e.missingFields?.[0];
        const at = first ? SECTIONS.findIndex((s) => s.key === sectionOf(first)) : -1;
        if (at >= 0) setIndex(at);
        try {
          const fresh = await api.getClient(draft.id);
          setDraft(fresh);
        } catch {
          /* the error above is already shown */
        }
      } else if (e instanceof ApiError && e.code === 'CLIENT_DRAFT_LOCKED') {
        try {
          setDraft(await api.getClient(draft.id));
        } catch {
          /* keep the locked message */
        }
      }
      // CLIENT_PHONE_UNAVAILABLE: the draft stays a draft; Discard is offered.
    } finally {
      setBusy(false);
    }
  }

  async function discard() {
    setConfirmDiscard(false);
    setBusy(true);
    setError(null);
    try {
      await api.deleteClient(draft.id);
      navigate('/clients', { replace: true });
    } catch (e) {
      setError(e);
      setBusy(false);
    }
  }

  const statusText = pickLabel(draft.statusLabel ?? config?.clientStatusLabels?.[draft.status], draft.status);
  const canSubmit = editable && draft.missingRequired.length === 0 && !dirty && !busy;

  return (
    <>
      <PageHeader title={draft.displayName} description={`${draft.phoneMasked} · ${statusText}`} />
      <p className="hint">
        <Link to="/clients">← All clients</Link>
      </p>
      <p>
        <StatusBadge tone={tone(draft.status)}>{statusText}</StatusBadge>{' '}
        {draft.expiresOn && isOpen(draft) && (
          <span className="hint">
            {draft.status === 'DRAFT' ? 'Open until' : 'Waiting until'} {draft.expiresOn}
          </span>
        )}
        {draft.status === 'ACCEPTED' && draft.acceptedOn && <span className="hint">Accepted {draft.acceptedOn}</span>}
      </p>
      {draft.status === 'ACCEPTED' && draft.referralId && (
        <p>
          <Link to="/referrals">See her in People who joined</Link>
        </p>
      )}
      {paused && <p className="notice">Your account is paused. You can look, but not change anything.</p>}
      {error != null && (
        <p className="error" role="alert">
          {clientErrorMessage(error, limit)}
          {error instanceof ApiError && error.code === 'CLIENT_PROFILE_INCOMPLETE' && error.missingFields?.length
            ? ` Please fill in: ${error.missingFields.join(', ')}.`
            : ''}
        </p>
      )}

      {draft.details === null && (
        <p className="hint">Her details are no longer kept on this screen.</p>
      )}

      {draft.details !== null && !editable && (
        <ReadOnlyProfile details={draft.details} />
      )}

      {editable && (
        <>
          <p className="hint" aria-label="Required fields left">
            {missingText(draft.missingRequired)}
          </p>
          <nav aria-label="Sections" className="toolbar">
            {SECTIONS.map((s, i) => (
              <button
                key={s.key}
                type="button"
                className={i === index ? '' : 'secondary'}
                aria-current={i === index ? 'step' : undefined}
                onClick={() => setIndex(i)}
              >
                {s.title}
              </button>
            ))}
          </nav>
          <div className="card form-card">
            <h2>{section.title}</h2>
            {section.fields.map((f) => (
              <FieldInput
                key={f.path}
                field={f}
                details={details}
                required={draft.missingRequired.includes(f.path)}
                onChange={(v) => setDetails((d) => setAnswer(d, f.path, v))}
              />
            ))}
            {section.siblings && (
              <Siblings
                rows={(getPath(details, 'familyDetails.siblings') as SiblingRow[] | undefined) ?? []}
                problems={problems}
                onChange={(rows) => setDetails((d) => setPath(d, 'familyDetails.siblings', rows))}
              />
            )}
            {problems.length > 0 && (
              <p className="error" role="alert">
                {problems.map((p) => p.message).join(' ')}
              </p>
            )}
            <div className="actions">
              <button type="button" onClick={() => void saveAndNext()} disabled={busy}>
                {index < SECTIONS.length - 1 ? 'Save and continue' : 'Save'}
              </button>
              <button type="button" className="secondary" onClick={() => void save()} disabled={busy}>
                Save
              </button>
              {index < SECTIONS.length - 1 && (
                <button type="button" className="secondary" onClick={skip} disabled={busy}>
                  Skip
                </button>
              )}
            </div>
          </div>

          <div className="card form-card">
            {dirty && <p className="hint">Save your changes before submitting.</p>}
            {confirming ? (
              <>
                <p>Once submitted you can't change it. Submit?</p>
                <div className="actions">
                  <button type="button" onClick={() => void submit()} disabled={busy}>
                    Yes, submit
                  </button>
                  <button type="button" className="secondary" onClick={() => setConfirming(false)}>
                    Cancel
                  </button>
                </div>
              </>
            ) : (
              <div className="actions">
                <button type="button" disabled={!canSubmit} onClick={() => setConfirming(true)}>
                  Submit to client
                </button>
              </div>
            )}
            {confirmDiscard ? (
              <div className="actions">
                <span>Discard this client?</span>
                <button type="button" onClick={() => void discard()} disabled={busy}>
                  Yes, discard
                </button>
                <button type="button" className="secondary" onClick={() => setConfirmDiscard(false)}>
                  Keep
                </button>
              </div>
            ) : (
              <button type="button" className="secondary" onClick={() => setConfirmDiscard(true)} disabled={busy}>
                Discard
              </button>
            )}
          </div>
        </>
      )}
    </>
  );
}

// ─── Inputs ──────────────────────────────────────────────────────────

function FieldInput({
  field,
  details,
  required,
  onChange,
}: {
  field: FieldDef;
  details: ClientDetails;
  required: boolean;
  onChange: (v: string) => void;
}) {
  const id = `f-${field.path.replace(/\./g, '-')}`;
  const value = (getPath(details, field.path) as string | undefined) ?? '';
  const label = required ? `${field.label} (required)` : field.label;
  return (
    <FormField id={id} label={label}>
      {(p) => {
        if (field.kind === 'ref') return <RefSelect {...p} field={field} details={details} value={value} onChange={onChange} />;
        if (field.kind === 'choice')
          return (
            <select {...p} value={value} onChange={(e) => onChange(e.target.value)}>
              <option value="">Not answered</option>
              {field.options?.map((o) => (
                <option key={o.value} value={o.value}>
                  {o.label}
                </option>
              ))}
            </select>
          );
        if (field.kind === 'longtext')
          return <textarea {...p} value={value} maxLength={field.maxLength} onChange={(e) => onChange(e.target.value)} />;
        return (
          <input
            {...p}
            type={field.kind === 'date' ? 'date' : 'text'}
            value={value}
            maxLength={field.maxLength}
            onChange={(e) => onChange(e.target.value)}
          />
        );
      }}
    </FormField>
  );
}

const REF_PARENT: Record<string, string | null> = {
  religion: null,
  community: 'religionDetails.religionCode',
  country: null,
  state: 'locationDetails.countryCode',
  city: 'locationDetails.stateCode',
};

/** A master-data dropdown whose options depend on its parent's chosen code. */
function RefSelect({
  field,
  details,
  value,
  onChange,
  ...aria
}: {
  field: FieldDef;
  details: ClientDetails;
  value: string;
  onChange: (v: string) => void;
  id: string;
}) {
  const { api } = usePortal();
  const kind = field.ref!;
  const parentPath = REF_PARENT[kind];
  const parent = parentPath ? ((getPath(details, parentPath) as string | undefined) ?? '') : null;
  const load = useCallback((): Promise<RefItem[]> => {
    switch (kind) {
      case 'religion':
        return api.getReligions();
      case 'country':
        return api.getCountries();
      case 'community':
        return parent ? api.getCommunities(parent) : Promise.resolve([]);
      case 'state':
        return parent ? api.getStates(parent) : Promise.resolve([]);
      default:
        return parent ? api.getCities(parent) : Promise.resolve([]);
    }
  }, [api, kind, parent]);
  const options = useAsync(load);
  const waiting = parentPath !== null && !parent;
  // A saved code the list does not (yet) contain is still shown, not lost.
  const items = options.data ?? [];
  const known = items.some((i) => i.code === value);
  return (
    <>
      <select {...aria} value={value} disabled={waiting || options.loading} onChange={(e) => onChange(e.target.value)}>
        <option value="">{waiting ? 'Choose the one above first' : options.loading ? 'Loading…' : 'Not answered'}</option>
        {value && !known && <option value={value}>{value}</option>}
        {items.map((i) => (
          <option key={i.code} value={i.code}>
            {i.label}
          </option>
        ))}
      </select>
      {options.error != null && <ErrorText error={options.error} onRetry={options.reload} />}
    </>
  );
}

function Siblings({
  rows,
  problems,
  onChange,
}: {
  rows: SiblingRow[];
  problems: { path: string; message: string }[];
  onChange: (rows: SiblingRow[]) => void;
}) {
  const set = (i: number, patch: Partial<SiblingRow>) =>
    onChange(rows.map((r, j) => (j === i ? { ...r, ...patch } : r)));
  return (
    <fieldset>
      <legend>Siblings</legend>
      {rows.map((r, i) => (
        <div key={i} className="sibling-row">
          <select
            aria-label={`Sibling ${i + 1} relation`}
            aria-invalid={problems.some((p) => p.path === `familyDetails.siblings[${i}].relation`) || undefined}
            value={r.relation ?? ''}
            onChange={(e) => set(i, { relation: e.target.value })}
          >
            <option value="">Brother or sister?</option>
            <option value="BROTHER">Brother</option>
            <option value="SISTER">Sister</option>
          </select>
          <input aria-label={`Sibling ${i + 1} name`} maxLength={50} value={r.name ?? ''} onChange={(e) => set(i, { name: e.target.value })} />
          <input
            aria-label={`Sibling ${i + 1} age`}
            inputMode="numeric"
            value={r.age === undefined ? '' : String(r.age)}
            onChange={(e) => set(i, { age: e.target.value })}
          />
          <button type="button" className="secondary" onClick={() => onChange(rows.filter((_, j) => j !== i))}>
            Remove
          </button>
        </div>
      ))}
      {rows.length < 10 && (
        <button type="button" className="secondary" onClick={() => onChange([...rows, {}])}>
          Add a sibling
        </button>
      )}
    </fieldset>
  );
}

function ReadOnlyProfile({ details }: { details: ClientDetails }) {
  const rows = SECTIONS.flatMap((s) =>
    s.fields
      .filter((f) => isAnswered(details, f.path))
      .map((f) => {
        // Master-data answers show the server's label ("Hindu"), not the code.
        const shown = f.kind === 'ref' ? getPath(details, f.path.replace(/Code$/, '')) : undefined;
        return [`${s.title}: ${f.label}`, String(shown ?? getPath(details, f.path))] as [string, string];
      }),
  );
  if (rows.length === 0) return <p className="hint">Nothing was filled in.</p>;
  return (
    <dl className="facts card">
      {rows.map(([k, v]) => (
        <div key={k} style={{ display: 'contents' }}>
          <dt>{k}</dt>
          <dd>{v}</dd>
        </div>
      ))}
    </dl>
  );
}
